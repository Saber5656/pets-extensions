# Typing With My Pets

macOS desktop overlay for practicing typing next to an independently running Codex Pet.

This app does not render or control the Pet. It watches for a small on-screen Codex-owned Pet window and places a transparent typing panel next to it.

| Pet position | Typing panel position |
|---|---|
| Left of the display center | Right side of the Pet |
| Right of the display center | Left side of the Pet |

## Requirements

- macOS
- Swift toolchain
- A Codex Pet already running on the desktop

## Run

```bash
./scripts/run.sh
```

Build only:

```bash
./scripts/build.sh
```

This creates:

```text
.build/manual/TypingWithMyPets.app
```

Test core logic:

```bash
./scripts/test.sh
```

`Package.swift` is included for normal SwiftPM-compatible environments, but the scripts above intentionally use `swiftc` directly so the app can still build if the local SwiftPM manifest runner is unhealthy.

## Controls

| Control | Action |
|---|---|
| Tap the Codex Pet | Toggle the typing panel open/closed |
| `×` | Close only the typing panel |
| `Esc` | Close only the typing panel |
| `⌘Q` | Quit the overlay app |
| `↻` | Restart current prompt |
| `→` | Next prompt |

## Notes

- The typing panel window is transparent and borderless.
- If the Codex Pet window is not detectable, the panel stays near the last known Pet position or the display center.
- The implementation uses macOS CoreGraphics on-screen window metadata. It does not inject UI into Codex and does not modify Codex Pet assets.
- Pet tap toggling while open is implemented by observing global left-click events and checking whether the click landed inside the tracked Pet window bounds.
- When the panel is closed, the app keeps an invisible click hotspot aligned over the tracked Pet so tapping the Pet can reopen the panel reliably.
