import AppKit
import CoreGraphics
import Foundation
import TypingWithMyPetsCore

private enum InputPlacement {
    case leftOfPet
    case rightOfPet
}

private enum ChatVisibility {
    case open
    case closed
}

private struct OverlayMetrics {
    let openSize = CGSize(width: 390, height: 132)
    let gap: CGFloat = 18

    func size(for visibility: ChatVisibility) -> CGSize {
        openSize
    }
}

private struct TrackedPetWindow: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let windowName: String
    let frame: CGRect
}

private final class CodexPetWindowTracker {
    private var previousWindowID: CGWindowID?
    private var lastFrame: CGRect?

    func currentPetWindow() -> TrackedPetWindow? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates = windows.compactMap { dictionary -> TrackedPetWindow? in
            guard
                let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
                ownerName.localizedCaseInsensitiveContains("codex"),
                let ownerPIDValue = Self.intValue(dictionary[kCGWindowOwnerPID as String]),
                let ownerPID = pid_t(exactly: ownerPIDValue),
                ownerPID != ownPID,
                let windowIDValue = Self.uint32Value(dictionary[kCGWindowNumber as String]),
                let windowID = CGWindowID(exactly: windowIDValue),
                let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
                let width = Self.cgFloatValue(bounds["Width"]),
                let height = Self.cgFloatValue(bounds["Height"]),
                let x = Self.cgFloatValue(bounds["X"]),
                let y = Self.cgFloatValue(bounds["Y"])
            else {
                return nil
            }

            let windowName = dictionary[kCGWindowName as String] as? String ?? ""
            let layer = Self.intValue(dictionary[kCGWindowLayer as String]) ?? 0
            let alpha = Self.cgFloatValue(dictionary[kCGWindowAlpha as String]) ?? 1
            guard alpha > 0.05, layer >= 0 else {
                return nil
            }

            let isPetSized = width >= 36 && height >= 36 && width <= 420 && height <= 420
            let nameSuggestsPet = windowName.localizedCaseInsensitiveContains("pet")
                || windowName.localizedCaseInsensitiveContains("kiro")
            guard isPetSized || nameSuggestsPet else {
                return nil
            }

            return TrackedPetWindow(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                windowName: windowName,
                frame: Self.convertCGWindowFrame(CGRect(x: x, y: y, width: width, height: height))
            )
        }

        guard !candidates.isEmpty else {
            return nil
        }

        let selected: TrackedPetWindow
        if let previousWindowID,
           let previous = candidates.first(where: { $0.windowID == previousWindowID }) {
            selected = previous
        } else if let lastFrame {
            selected = candidates.min { lhs, rhs in
                distance(lhs.frame.center, lastFrame.center) < distance(rhs.frame.center, lastFrame.center)
            } ?? candidates[0]
        } else {
            selected = candidates.sorted { lhs, rhs in
                lhs.frame.area < rhs.frame.area
            }[0]
        }

        previousWindowID = selected.windowID
        lastFrame = selected.frame
        return selected
    }

    func fallbackFrame() -> CGRect {
        if let lastFrame {
            return lastFrame
        }

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(x: screen.midX - 72, y: screen.midY - 78, width: 144, height: 156)
    }

    private static func convertCGWindowFrame(_ cgFrame: CGRect) -> CGRect {
        let maxScreenY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(
            x: cgFrame.minX,
            y: maxScreenY - cgFrame.minY - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }

    private static func cgFloatValue(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Float {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        if let value = value as? NSNumber {
            return CGFloat(value.doubleValue)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func uint32Value(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt32(value)
        }
        if let value = value as? NSNumber {
            return value.uint32Value
        }
        return nil
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class TransparentTypingTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return
        }

        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}

private final class InputPanelView: NSView {
    let targetLabel = NSTextField(labelWithString: "")
    let statsLabel = NSTextField(labelWithString: "")
    let textView = TransparentTypingTextView()
    let restartButton = NSButton(title: "↻", target: nil, action: nil)
    let nextButton = NSButton(title: "→", target: nil, action: nil)
    let closeButton = NSButton(title: "×", target: nil, action: nil)

    var visibility: ChatVisibility = .open {
        didSet { applyVisibility() }
    }

    private let scrollView = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        targetLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        targetLabel.textColor = .labelColor
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.maximumNumberOfLines = 2

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statsLabel.textColor = .secondaryLabelColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView

        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor

        [restartButton, nextButton, closeButton].forEach { button in
            button.isBordered = false
            button.font = .systemFont(ofSize: 16, weight: .bold)
            button.contentTintColor = .labelColor
        }

        addSubview(targetLabel)
        addSubview(statsLabel)
        addSubview(scrollView)
        addSubview(restartButton)
        addSubview(nextButton)
        addSubview(closeButton)
        applyVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard visibility == .open else {
            return
        }

        let radius: CGFloat = 16
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        NSColor.windowBackgroundColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func layout() {
        super.layout()

        let padding: CGFloat = 14
        let buttonSize: CGFloat = 24
        let topY = bounds.height - padding - 28

        closeButton.frame = CGRect(x: bounds.width - padding - buttonSize, y: topY + 2, width: buttonSize, height: buttonSize)
        nextButton.frame = CGRect(x: closeButton.frame.minX - buttonSize - 4, y: topY + 2, width: buttonSize, height: buttonSize)
        restartButton.frame = CGRect(x: nextButton.frame.minX - buttonSize - 4, y: topY + 2, width: buttonSize, height: buttonSize)

        targetLabel.frame = CGRect(
            x: padding,
            y: bounds.height - padding - 38,
            width: restartButton.frame.minX - padding - 8,
            height: 36
        )

        scrollView.frame = CGRect(
            x: padding,
            y: padding + 24,
            width: bounds.width - padding * 2,
            height: 42
        )
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)

        statsLabel.frame = CGRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: 18
        )
    }

    private func applyVisibility() {
        let isOpen = visibility == .open
        targetLabel.isHidden = !isOpen
        statsLabel.isHidden = !isOpen
        scrollView.isHidden = !isOpen
        restartButton.isHidden = !isOpen
        nextButton.isHidden = !isOpen
        closeButton.isHidden = !isOpen
        needsLayout = true
        needsDisplay = true
    }

    var onClosedClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if visibility == .closed {
            onClosedClick?()
            return
        }
        window?.performDrag(with: event)
    }
}

private final class OverlayRootView: NSView {
    let inputPanel: InputPanelView

    init(inputPanel: InputPanelView) {
        self.inputPanel = inputPanel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(inputPanel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        inputPanel.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        inputPanel.frame.contains(point) ? super.hitTest(point) : nil
    }
}

private final class OverlayController: NSObject, NSTextViewDelegate {
    private let metrics = OverlayMetrics()
    private let tracker = CodexPetWindowTracker()
    private let rootView: OverlayRootView
    private let inputPanel: InputPanelView
    private weak var window: NSWindow?
    private var updateTimer: Timer?
    private var petClickMonitor: Any?
    private var exercises = Exercise.defaults
    private var exerciseIndex = 0
    private var session: TypingSession
    private var chatVisibility: ChatVisibility = .open
    private var lastDetectedPetFrame: CGRect?
    private var lastPetToggleAt: TimeInterval = 0

    override init() {
        inputPanel = InputPanelView(frame: CGRect(origin: .zero, size: metrics.openSize))
        rootView = OverlayRootView(inputPanel: inputPanel)
        session = TypingSession(exercise: exercises[0])
        super.init()
        inputPanel.textView.delegate = self
        inputPanel.textView.onEscape = { [weak self] in self?.setChatVisible(false) }
        inputPanel.onClosedClick = { [weak self] in self?.setChatVisible(true) }
        inputPanel.restartButton.target = self
        inputPanel.restartButton.action = #selector(restart)
        inputPanel.nextButton.target = self
        inputPanel.nextButton.action = #selector(nextExercise)
        inputPanel.closeButton.target = self
        inputPanel.closeButton.action = #selector(closeChat)
        loadExercise(index: 0)
    }

    deinit {
        if let petClickMonitor {
            NSEvent.removeMonitor(petClickMonitor)
        }
    }

    func initialFrame(on screen: NSScreen) -> CGRect {
        let size = metrics.size(for: chatVisibility)
        return CGRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func install(in window: NSWindow) {
        self.window = window
        window.contentView = rootView
        window.setContentSize(metrics.size(for: chatVisibility))
        window.makeFirstResponder(inputPanel.textView)
        startTimer()
        startPetClickMonitor()
    }

    private func startTimer() {
        updateTimer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.updateOverlayPosition()
            self?.updateStats()
        }
        if let updateTimer {
            RunLoop.main.add(updateTimer, forMode: .common)
        }
    }

    private func startPetClickMonitor() {
        petClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.toggleChatIfPetWasClicked(at: location)
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        session.update(rawInput: inputPanel.textView.string)
        if inputPanel.textView.string != session.input {
            inputPanel.textView.string = session.input
            inputPanel.textView.setSelectedRange(NSRange(location: session.input.count, length: 0))
        }
        updateStats()
    }

    @objc private func restart() {
        loadExercise(index: exerciseIndex)
    }

    @objc private func nextExercise() {
        loadExercise(index: (exerciseIndex + 1) % exercises.count)
    }

    @objc private func closeChat() {
        setChatVisible(false)
    }

    private func setChatVisible(_ visible: Bool) {
        chatVisibility = visible ? .open : .closed
        inputPanel.visibility = chatVisibility

        if visible {
            updateOverlayPosition()
            window?.orderFrontRegardless()
            window?.makeFirstResponder(inputPanel.textView)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            updateOverlayPosition()
            window?.orderFrontRegardless()
        }
    }

    private func toggleChatIfPetWasClicked(at location: CGPoint) {
        guard let petFrame = lastDetectedPetFrame?.insetBy(dx: -12, dy: -12),
              petFrame.contains(location)
        else {
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastPetToggleAt > 0.25 else {
            return
        }
        lastPetToggleAt = now
        setChatVisible(chatVisibility == .closed)
    }

    private func loadExercise(index: Int) {
        exerciseIndex = max(0, min(index, exercises.count - 1))
        session = TypingSession(exercise: exercises[exerciseIndex])
        inputPanel.targetLabel.stringValue = exercises[exerciseIndex].text
        inputPanel.textView.string = ""
        inputPanel.textView.isEditable = true
        updateStats()
    }

    private func updateStats() {
        let metrics = session.metrics
        inputPanel.statsLabel.stringValue = "\(Int(metrics.wpm.rounded())) WPM · \(Int(metrics.accuracy.rounded()))% · \(session.correctStreak) streak · \(formatDuration(metrics.elapsed))"
    }

    private func resizeAndReposition() {
        guard let window else { return }
        let oldCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let size = metrics.size(for: chatVisibility)
        var frame = CGRect(
            x: oldCenter.x - size.width / 2,
            y: oldCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        frame = clamped(frame, in: bestScreen(for: oldCenter).visibleFrame)
        window.setFrame(frame, display: true)
        rootView.needsLayout = true
    }

    private func updateOverlayPosition() {
        guard let window else { return }

        let petWindow = tracker.currentPetWindow()
        if let petWindow {
            lastDetectedPetFrame = petWindow.frame
        }
        let petFrame = petWindow?.frame ?? lastDetectedPetFrame ?? tracker.fallbackFrame()
        let screen = bestScreen(for: petFrame.center)
        if chatVisibility == .closed {
            let desired = petFrame.insetBy(dx: -12, dy: -12)
            window.setFrame(clamped(desired, in: screen.visibleFrame), display: true)
            return
        }

        let placement: InputPlacement = petFrame.center.x < screen.visibleFrame.midX ? .rightOfPet : .leftOfPet
        let size = metrics.size(for: chatVisibility)

        let x: CGFloat
        switch placement {
        case .rightOfPet:
            x = petFrame.maxX + metrics.gap
        case .leftOfPet:
            x = petFrame.minX - metrics.gap - size.width
        }

        let desired = CGRect(
            x: x,
            y: petFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(clamped(desired, in: screen.visibleFrame), display: true)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var controller: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            NSApp.terminate(nil)
            return
        }

        let controller = OverlayController()
        let window = OverlayWindow(
            contentRect: controller.initialFrame(on: screen),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.title = "Typing With My Pets"

        controller.install(in: window)
        self.controller = controller
        self.window = window

        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private func bestScreen(for point: CGPoint) -> NSScreen {
    NSScreen.screens.first(where: { $0.visibleFrame.contains(point) })
        ?? NSScreen.main
        ?? NSScreen.screens.first
        ?? NSScreen()
}

private func clamped(_ frame: CGRect, in bounds: CGRect) -> CGRect {
    CGRect(
        x: min(max(frame.minX, bounds.minX), bounds.maxX - frame.width),
        y: min(max(frame.minY, bounds.minY), bounds.maxY - frame.height),
        width: frame.width,
        height: frame.height
    )
}

private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        width * height
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
