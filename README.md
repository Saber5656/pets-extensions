# Typing With My Pets

macOS desktop overlay for practicing typing and chatting next to an independently running Codex Pet.

This app does not render or control the Pet. It watches for a small on-screen Codex-owned Pet window and places a transparent input panel next to it.

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

## Releases

See [RELEASE_NOTES.md](RELEASE_NOTES.md) before cutting or downloading a release.

The current `v0.1.0` release plan is a developer preview. The app bundle is
unsigned and not notarized, so macOS may show a Gatekeeper warning on first
launch.

## Controls

| Control | Action |
|---|---|
| Two-finger tap / secondary click on the Codex Pet | Toggle the typing panel open/closed |
| `×` | Close only the typing panel |
| `Esc` | Close only the typing panel |
| `⌘Q` | Quit the overlay app |
| `⌨` | Typing practice mode |
| Chat bubble | Conversation mode |
| `Return` | Submit the current attempt and show the result score |
| `Return` after submitting | Move to the next prompt |
| `Return` in conversation mode | Send the message |
| `Shift` + `Return` in conversation mode | Insert a newline |
| `↻` | Restart current prompt |
| `→` | Next prompt |

## Conversation Mode

Conversation mode uses Apple's local FoundationModels API when it is available on macOS 26 or later. If the local model is unavailable, the panel shows a short unavailable reason instead of using a cloud or rule-based fallback chat.

The app handles a few action intents before asking the model:

| Intent | Behavior |
|---|---|
| One-time reminder with a clear future date and time | Creates an Apple Reminders item through EventKit |
| `取り消して` after creating a reminder | Removes the last reminder created by this app session |
| Clock alarm requests | Says Clock alarms are not supported yet |
| Coding, repository, research, app opening, or Computer Use requests | Asks for confirmation, then passes a task prompt to Codex App Server through the local Codex CLI |
| Unsupported direct OS lifecycle requests | Says the action is not supported by the pet itself |

Codex handoff uses Codex's own login, approval, and Computer Use flow. The pet only prepares the task text and starts the handoff after confirmation.

For reminder times from `1時` through `12時`, include `午前` or `午後`; otherwise the pet asks for clarification instead of guessing.
If you answer that clarification in the next message, the pet merges it with the pending reminder request.

Codex handoff uses the local Codex CLI. You can override the defaults with:

| Environment variable | Purpose |
|---|---|
| `TWMP_CODEX_CLI_PATH` | Absolute path to the Codex CLI used for App Server handoff |
| `TWMP_CODEX_WORKDIR` | Working directory used when starting the Codex handoff |

## Notes

- The typing panel window is transparent and borderless.
- If the Codex Pet window is not detectable, the panel stays hidden.
- The implementation uses macOS CoreGraphics on-screen window metadata. It does not inject UI into Codex and does not modify Codex Pet assets.
- Pet toggling is implemented by observing global secondary-click events and checking whether the click landed inside a tightened Pet body region.
- When the panel is closed, the app ignores mouse events and relies on the secondary-click monitor, so the invisible overlay no longer steals ordinary Pet clicks.
- Reminders require macOS Reminders permission and are only created after an explicit user request.
