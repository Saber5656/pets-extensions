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

private enum BubbleTailSide {
    case left
    case right
}

private struct OverlayMetrics {
    let openSize = CGSize(width: 408, height: 160)
    let tailDepth: CGFloat = 24
    let tailCenterRatioFromBottom: CGFloat = 0.25
    let gapWhenPanelLeftOfPet: CGFloat = -28
    let gapWhenPanelRightOfPet: CGFloat = 42
    let petMouthYRatio: CGFloat = 0.62

    var tailCenterY: CGFloat {
        openSize.height * tailCenterRatioFromBottom
    }

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

    private static func convertCGWindowFrame(_ cgFrame: CGRect) -> CGRect {
        let mainDisplayHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        return CGRect(
            x: cgFrame.minX,
            y: mainDisplayHeight - cgFrame.minY - cgFrame.height,
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

private struct PetRegionResolver {
    func visibleFrame(for petWindow: TrackedPetWindow, on screen: NSScreen) -> CGRect {
        let frame = petWindow.frame
        guard frame.width > 0, frame.height > 0 else {
            return frame
        }

        let visualWidth = min(frame.width, max(72, min(frame.width * 0.72, frame.height * 0.76)))
        let visualHeight = min(frame.height, max(72, frame.height * 0.92))
        let horizontalInset = max(0, frame.width - visualWidth)
        let isOnLeftSide = frame.center.x < screen.visibleFrame.midX
        let x = isOnLeftSide
            ? frame.minX + horizontalInset * 0.18
            : frame.maxX - visualWidth - horizontalInset * 0.18
        let y = frame.minY + max(0, frame.height - visualHeight) * 0.45

        return CGRect(x: x, y: y, width: visualWidth, height: visualHeight)
    }

    func containsPetBody(_ point: CGPoint, in visualFrame: CGRect) -> Bool {
        guard visualFrame.contains(point), visualFrame.width > 0, visualFrame.height > 0 else {
            return false
        }

        let normalizedX = (point.x - visualFrame.midX) / (visualFrame.width / 2)
        let normalizedY = (point.y - visualFrame.midY) / (visualFrame.height / 2)
        let upperHead = pow(normalizedX / 0.92, 2) + pow((normalizedY - 0.22) / 0.9, 2) <= 1
        let lowerBody = abs(normalizedX) <= 0.8 && normalizedY >= -0.92 && normalizedY <= 0.3
        let tailAndFeetBand = abs(normalizedX) <= 0.95 && normalizedY >= -1 && normalizedY <= -0.58

        return upperHead || lowerBody || tailAndFeetBand
    }
}

private final class OverlayWindow: NSWindow {
    var acceptsKeyboardFocus = true

    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { acceptsKeyboardFocus }
}

private final class TransparentTypingTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onSubmit: (() -> Void)?

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

        if event.keyCode == 36 || event.keyCode == 76 {
            if hasMarkedText() {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
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

    var tailSide: BubbleTailSide = .right {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    var tailCenterY: CGFloat {
        didSet { needsDisplay = true }
    }

    private let scrollView = NSScrollView()
    private let tailDepth: CGFloat
    private let tailHalfHeight: CGFloat = 18

    init(frame frameRect: NSRect, tailDepth: CGFloat, tailCenterY: CGFloat) {
        self.tailDepth = tailDepth
        self.tailCenterY = tailCenterY
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        targetLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        targetLabel.textColor = .labelColor
        targetLabel.lineBreakMode = .byWordWrapping
        targetLabel.maximumNumberOfLines = 3
        targetLabel.usesSingleLineMode = false
        targetLabel.cell?.wraps = true
        targetLabel.cell?.isScrollable = false
        targetLabel.cell?.lineBreakMode = .byWordWrapping

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
        textView.textContainer?.lineBreakMode = .byWordWrapping
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

        let radius: CGFloat = 28
        let bodyRect = bubbleBodyRect.insetBy(dx: 1, dy: 1)
        let fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.24)
        let strokeColor = NSColor.labelColor.withAlphaComponent(0.34)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
        let tailY = min(max(tailCenterY, bodyRect.minY + radius + tailHalfHeight), bodyRect.maxY - radius - tailHalfHeight)
        let tailPath = NSBezierPath()
        let tailStrokePath = NSBezierPath()

        switch tailSide {
        case .left:
            let tip = NSPoint(x: bounds.minX + 1, y: tailY)
            let upper = NSPoint(x: bodyRect.minX + 2, y: tailY + tailHalfHeight)
            let lower = NSPoint(x: bodyRect.minX + 2, y: tailY - tailHalfHeight)
            tailPath.move(to: tip)
            tailPath.curve(
                to: upper,
                controlPoint1: NSPoint(x: tip.x + tailDepth * 0.28, y: tailY + tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: upper.x - tailDepth * 0.28, y: upper.y - tailHalfHeight * 0.08)
            )
            tailPath.curve(
                to: lower,
                controlPoint1: NSPoint(x: upper.x - tailDepth * 0.38, y: tailY + tailHalfHeight * 0.15),
                controlPoint2: NSPoint(x: lower.x - tailDepth * 0.38, y: tailY - tailHalfHeight * 0.15)
            )
            tailPath.curve(
                to: tip,
                controlPoint1: NSPoint(x: lower.x - tailDepth * 0.28, y: lower.y + tailHalfHeight * 0.08),
                controlPoint2: NSPoint(x: tip.x + tailDepth * 0.28, y: tailY - tailHalfHeight * 0.22)
            )
            tailPath.close()
            tailStrokePath.move(to: tip)
            tailStrokePath.curve(
                to: upper,
                controlPoint1: NSPoint(x: tip.x + tailDepth * 0.28, y: tailY + tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: upper.x - tailDepth * 0.28, y: upper.y - tailHalfHeight * 0.08)
            )
            tailStrokePath.move(to: tip)
            tailStrokePath.curve(
                to: lower,
                controlPoint1: NSPoint(x: tip.x + tailDepth * 0.28, y: tailY - tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: lower.x - tailDepth * 0.28, y: lower.y + tailHalfHeight * 0.08)
            )
        case .right:
            let tip = NSPoint(x: bounds.maxX - 1, y: tailY)
            let upper = NSPoint(x: bodyRect.maxX - 2, y: tailY + tailHalfHeight)
            let lower = NSPoint(x: bodyRect.maxX - 2, y: tailY - tailHalfHeight)
            tailPath.move(to: tip)
            tailPath.curve(
                to: upper,
                controlPoint1: NSPoint(x: tip.x - tailDepth * 0.28, y: tailY + tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: upper.x + tailDepth * 0.28, y: upper.y - tailHalfHeight * 0.08)
            )
            tailPath.curve(
                to: lower,
                controlPoint1: NSPoint(x: upper.x + tailDepth * 0.38, y: tailY + tailHalfHeight * 0.15),
                controlPoint2: NSPoint(x: lower.x + tailDepth * 0.38, y: tailY - tailHalfHeight * 0.15)
            )
            tailPath.curve(
                to: tip,
                controlPoint1: NSPoint(x: lower.x + tailDepth * 0.28, y: lower.y + tailHalfHeight * 0.08),
                controlPoint2: NSPoint(x: tip.x - tailDepth * 0.28, y: tailY - tailHalfHeight * 0.22)
            )
            tailPath.close()
            tailStrokePath.move(to: tip)
            tailStrokePath.curve(
                to: upper,
                controlPoint1: NSPoint(x: tip.x - tailDepth * 0.28, y: tailY + tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: upper.x + tailDepth * 0.28, y: upper.y - tailHalfHeight * 0.08)
            )
            tailStrokePath.move(to: tip)
            tailStrokePath.curve(
                to: lower,
                controlPoint1: NSPoint(x: tip.x - tailDepth * 0.28, y: tailY - tailHalfHeight * 0.22),
                controlPoint2: NSPoint(x: lower.x + tailDepth * 0.28, y: lower.y + tailHalfHeight * 0.08)
            )
        }

        fillColor.setFill()
        tailPath.fill()
        bodyPath.fill()

        strokeColor.setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()
        tailStrokePath.lineWidth = 1
        tailStrokePath.stroke()
    }

    override func layout() {
        super.layout()

        let padding: CGFloat = 14
        let buttonSize: CGFloat = 24
        let bodyRect = bubbleBodyRect.insetBy(dx: 1, dy: 1)
        let contentMinX = bodyRect.minX + padding
        let contentMaxX = bodyRect.maxX - padding
        let topY = bodyRect.maxY - padding - 28

        closeButton.frame = CGRect(x: contentMaxX - buttonSize, y: topY + 2, width: buttonSize, height: buttonSize)
        nextButton.frame = CGRect(x: closeButton.frame.minX - buttonSize - 4, y: topY + 2, width: buttonSize, height: buttonSize)
        restartButton.frame = CGRect(x: nextButton.frame.minX - buttonSize - 4, y: topY + 2, width: buttonSize, height: buttonSize)

        targetLabel.frame = CGRect(
            x: contentMinX,
            y: bodyRect.maxY - padding - 62,
            width: restartButton.frame.minX - contentMinX - 8,
            height: 58
        )

        scrollView.frame = CGRect(
            x: contentMinX,
            y: bodyRect.minY + padding + 26,
            width: contentMaxX - contentMinX,
            height: 42
        )
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)

        statsLabel.frame = CGRect(
            x: contentMinX,
            y: bodyRect.minY + padding,
            width: contentMaxX - contentMinX,
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

    private var bubbleBodyRect: CGRect {
        switch tailSide {
        case .left:
            return bounds.insetBy(dx: 0, dy: 0).divided(atDistance: tailDepth, from: .minXEdge).remainder
        case .right:
            return bounds.insetBy(dx: 0, dy: 0).divided(atDistance: tailDepth, from: .maxXEdge).remainder
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard visibility == .open else { return }
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
    private let petRegion = PetRegionResolver()
    private let rootView: OverlayRootView
    private let inputPanel: InputPanelView
    private weak var window: NSWindow?
    private var updateTimer: Timer?
    private var petClickMonitor: Any?
    private var exercises = Exercise.defaults.shuffled()
    private var exerciseIndex = 0
    private var session: TypingSession
    private var chatVisibility: ChatVisibility = .open
    private var lastPetToggleAt: TimeInterval = 0
    private var submittedAt: TimeInterval?
    private var petIsAvailable = false

    override init() {
        inputPanel = InputPanelView(
            frame: CGRect(origin: .zero, size: metrics.openSize),
            tailDepth: metrics.tailDepth,
            tailCenterY: metrics.tailCenterY
        )
        rootView = OverlayRootView(inputPanel: inputPanel)
        session = TypingSession(exercise: exercises[0])
        super.init()
        inputPanel.textView.delegate = self
        inputPanel.textView.onEscape = { [weak self] in self?.setChatVisible(false) }
        inputPanel.textView.onSubmit = { [weak self] in self?.submitOrAdvance() }
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
        window.ignoresMouseEvents = chatVisibility == .closed
        window.makeFirstResponder(inputPanel.textView)
        startTimer()
        startPetClickMonitor()
        updateOverlayPosition()
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
        petClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.toggleChatIfPetWasSecondaryClicked(at: location)
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        guard submittedAt == nil else {
            syncTextViewToSessionInput()
            updateStats()
            return
        }

        guard !inputPanel.textView.hasMarkedText() else {
            updateStats()
            return
        }

        session.update(rawInput: inputPanel.textView.string)
        syncTextViewToSessionInput()
        updateStats()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard chatVisibility == .open, !inputPanel.textView.hasMarkedText() else {
            return
        }
        moveInputCaretToEnd()
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
        inputPanel.textView.isEditable = visible && submittedAt == nil
        window?.ignoresMouseEvents = !visible

        if visible {
            (window as? OverlayWindow)?.acceptsKeyboardFocus = true
            updateOverlayPosition()
            guard petIsAvailable else {
                return
            }
            window?.orderFrontRegardless()
            window?.makeKey()
            window?.makeFirstResponder(inputPanel.textView)
            moveInputCaretToEnd()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window?.makeFirstResponder(nil)
            (window as? OverlayWindow)?.acceptsKeyboardFocus = false
            window?.resignKey()
            updateOverlayPosition()
        }
    }

    private func toggleChatIfPetWasSecondaryClicked(at location: CGPoint) {
        guard let currentPetWindow = tracker.currentPetWindow() else {
            petIsAvailable = false
            window?.orderOut(nil)
            return
        }

        let screen = bestScreen(for: currentPetWindow.frame.center)
        let petVisualFrame = petRegion.visibleFrame(for: currentPetWindow, on: screen)
        petIsAvailable = true

        guard petRegion.containsPetBody(location, in: petVisualFrame) else { return }

        let now = CACurrentMediaTime()
        guard now - lastPetToggleAt > 0.25 else {
            return
        }
        lastPetToggleAt = now
        setChatVisible(chatVisibility == .closed)
    }

    private func submitOrAdvance() {
        guard chatVisibility == .open else {
            return
        }

        if submittedAt != nil {
            nextExercise()
            return
        }

        submittedAt = Date().timeIntervalSince1970
        syncTextViewToSessionInput()
        inputPanel.textView.isEditable = false
        updateStats()
    }

    private func loadExercise(index: Int) {
        exerciseIndex = max(0, min(index, exercises.count - 1))
        submittedAt = nil
        session = TypingSession(exercise: exercises[exerciseIndex])
        inputPanel.targetLabel.stringValue = exercises[exerciseIndex].text
        inputPanel.textView.string = ""
        inputPanel.textView.isEditable = true
        moveInputCaretToEnd()
        updateStats()
    }

    private func syncTextViewToSessionInput() {
        guard !inputPanel.textView.hasMarkedText() else {
            return
        }

        if inputPanel.textView.string != session.input {
            inputPanel.textView.string = session.input
        }
        moveInputCaretToEnd()
    }

    private func moveInputCaretToEnd() {
        guard !inputPanel.textView.hasMarkedText() else {
            return
        }

        let endRange = NSRange(location: inputPanel.textView.string.count, length: 0)
        if inputPanel.textView.selectedRange() != endRange {
            inputPanel.textView.setSelectedRange(endRange)
        }
    }

    private func updateStats() {
        let metrics = session.metrics(at: session.completedAt ?? submittedAt ?? Date().timeIntervalSince1970)
        let score = typingScore(for: metrics)
        let progress = Int((metrics.progress * 100).rounded())
        let wpm = Int(metrics.wpm.rounded())
        let accuracy = Int(metrics.accuracy.rounded())
        let errors = max(metrics.totalErrors, metrics.liveErrors)

        if submittedAt != nil {
            inputPanel.statsLabel.stringValue = "Result \(score) · \(wpm) WPM · \(accuracy)% acc · \(progress)% done · \(errors) err · Enter next"
        } else if metrics.completed {
            inputPanel.statsLabel.stringValue = "Score \(score) · Complete · \(wpm) WPM · \(accuracy)% acc · Enter result"
        } else {
            inputPanel.statsLabel.stringValue = "Score \(score) · \(wpm) WPM · \(accuracy)% acc · \(progress)% done · \(errors) err"
        }
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

        guard let petWindow = tracker.currentPetWindow() else {
            petIsAvailable = false
            window.makeFirstResponder(nil)
            (window as? OverlayWindow)?.acceptsKeyboardFocus = false
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            return
        }

        let detectedScreen = bestScreen(for: petWindow.frame.center)
        let petFrame = petRegion.visibleFrame(for: petWindow, on: detectedScreen)
        petIsAvailable = true
        let screen = bestScreen(for: petFrame.center)
        if chatVisibility == .closed {
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            return
        }

        let placement: InputPlacement = petFrame.center.x < screen.visibleFrame.midX ? .rightOfPet : .leftOfPet
        let size = metrics.size(for: chatVisibility)
        inputPanel.tailSide = placement == .rightOfPet ? .left : .right

        let x: CGFloat
        switch placement {
        case .rightOfPet:
            x = petFrame.maxX + metrics.gapWhenPanelRightOfPet
        case .leftOfPet:
            x = petFrame.minX - metrics.gapWhenPanelLeftOfPet - size.width
        }

        let mouthY = petFrame.minY + petFrame.height * metrics.petMouthYRatio
        let desired = CGRect(
            x: x,
            y: mouthY - metrics.tailCenterY,
            width: size.width,
            height: size.height
        )
        window.setFrame(clamped(desired, in: screen.visibleFrame), display: true)
        window.ignoresMouseEvents = false
        (window as? OverlayWindow)?.acceptsKeyboardFocus = true

        if !window.isVisible {
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(inputPanel.textView)
        }
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
