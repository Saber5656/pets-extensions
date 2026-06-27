# Release Notes

## Unreleased

- Adds a conversation mode toggle next to typing practice mode.
- Uses Apple FoundationModels for local conversation on supported macOS versions, with no cloud or rule-based fallback chat.
- Adds EventKit Reminders support for explicit one-time reminder requests with a clear future date and time.
- Adds one-step undo for the last reminder created during the app session.
- Adds one-turn reminder clarification merging for follow-up answers like `午後`.
- Adds confirmation-gated Codex App Server handoff for coding, research, repository, app opening, and Computer Use style requests through the local Codex CLI.
- Adds Codex handoff workdir override via `TWMP_CODEX_WORKDIR`.
- Keeps app launching and macOS operation out of the pet's direct responsibility; Codex owns delegated app/GUI work.

## v0.1.0

Initial developer preview of Typing With My Pets.

### Highlights

- Shows a transparent typing practice panel next to a running Codex Pet.
- Positions the panel on the opposite side of the Pet based on screen location.
- Toggles the panel with a secondary click on the Pet body.
- Includes short typing prompts, score feedback, WPM, accuracy, progress, and errors.
- Adds a minimal macOS GitHub Actions CI check for smoke tests and app bundle builds.

### macOS Security Notice

This is an unsigned and non-notarized developer preview build.

macOS may show a Gatekeeper warning when opening the app for the first time.
Only run this build if you trust this repository and understand that it has not
been signed with a Developer ID or notarized by Apple.

Apple explains that macOS checks Developer ID signatures and, on macOS Catalina
and later, notarization for software distributed outside the App Store. Without
those checks, macOS cannot verify the developer identity or confirm that Apple's
notarization service found no known malware.

Reference: https://support.apple.com/en-us/102445

### Why This Notice Exists

- Users may otherwise confuse the Gatekeeper warning with an app crash or broken release.
- Managed Macs may block unsigned or non-notarized software by policy.
- The current release is intended for self-use and developer testing, not broad public distribution.
- Documenting this limitation makes the expected first-run behavior explicit before download.

### Distribution Policy

- `v0.1.0` can be released as a developer preview.
- Do not describe the artifact as a fully trusted public macOS distribution build.
- If the project is distributed to general users, add Developer ID signing and Apple notarization first.

### Validation

- `./scripts/test.sh`
- `./scripts/build.sh`
- GitHub Actions `CI / Build and smoke test` on `main`
