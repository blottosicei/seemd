# seemd

A lightweight, native macOS Markdown **viewer** — VS Code-quality rendering with native performance.

> SwiftUI · `swift-markdown` parsing · native render · `Splash` syntax highlighting · macOS 14+

## Status

Early open-source preview. The MVP viewer (open `.md`, GFM render, TOC, theme, live reload, search, zoom, tabs) and a toggleable split editor with live preview are working; continuous editor↔preview scroll sync lives on a feature branch. Issues and PRs welcome.

> **Syntax highlighting note:** highlighting is powered by [Splash](https://github.com/JohnSundell/Splash), which ships a Swift grammar only. Swift code fences are fully tokenized; other languages (JS/TS/Python/JSON/Shell/Bash) are recognized and rendered as monospaced code on the themed background but are not token-colored yet. Broader language coverage is on the backlog.

## Build

Requires Swift 5.9+ (Command Line Tools or Xcode).

```sh
swift build -c release
./scripts/bundle.sh release   # produces seemd.app (ad-hoc signed)
```

Run the self-test suite (XCTest is unavailable under CLT; use the custom runner instead):

```sh
swift run seemd-selftest
```

### Build a distributable DMG

```sh
./scripts/make-dmg.sh         # produces dist/seemd.dmg
```

`make-dmg.sh` calls `bundle.sh` automatically if `seemd.app` is not already present.

## Install (release `.dmg`)

Download the latest `.dmg` from [Releases](../../releases), open it, and drag **seemd** to Applications.

### Gatekeeper bypass (ad-hoc build)

Because the release build is ad-hoc signed (not notarized), macOS may block it on first launch with *"Apple cannot verify…"*. To open it once:

- **macOS 15 (Sequoia) and later** — click **Done** on the dialog, open **System Settings ▸ Privacy & Security**, scroll to the *"'seemd' was blocked"* entry, click **Open Anyway**, then confirm.
- **macOS 14 and earlier** — right-click (or Control-click) **seemd.app**, choose **Open**, then confirm **Open** in the dialog.
- **Or from the terminal**, strip the quarantine attribute:
  ```sh
  xattr -dr com.apple.quarantine /Applications/seemd.app
  ```

This is only needed once per machine.

## Auto-update (Sparkle)

seemd updates itself with [Sparkle](https://sparkle-project.org/) — **no Apple Developer account required**. Update integrity is guaranteed by an **EdDSA signature** (Sparkle's `SUPublicEDKey`) instead of Apple notarization: the app only installs an update whose archive is signed by the project's private key. The app checks the feed on launch and daily (`SUScheduledCheckInterval`), and **App menu ▸ Check for Updates…** triggers a manual check.

- **Feed:** [`appcast.xml`](appcast.xml) on `main`, served via `raw.githubusercontent.com` (`SUFeedURL`).
- **Binaries:** `.app` zips uploaded as GitHub Release assets.
- **Caveat:** because builds are unsigned/un-notarized, the **first launch still needs the Gatekeeper bypass above**. Subsequent in-app updates apply without that step.

### Cutting an auto-update release

The EdDSA private signing key lives in the maintainer's **macOS Keychain** (created once with Sparkle's `generate_keys`; never committed). So Sparkle releases are cut locally:

```sh
./scripts/release.sh 0.2.0
```

This bumps the version, builds + bundles `seemd.app` (embedding `Sparkle.framework`), zips it, signs the zip with the Keychain key, regenerates `appcast.xml`, creates the GitHub release with the zip, and commits + pushes `appcast.xml`. macOS will prompt once for Keychain access to the signing key — choose **Always Allow**. Existing users are offered the new version on their next check.

> Builds are **arm64-only** (SwiftPM builds for the host arch); the embedded Sparkle framework is universal but the app itself targets Apple Silicon.

## CI / Release workflow

- **CI** (`.github/workflows/ci.yml`): runs on every push and pull request — `swift build` + `swift run seemd-selftest`.
- **Release** (`.github/workflows/release.yml`): triggered by a `v*` tag — builds, self-tests, bundles, creates `dist/seemd.dmg` via `scripts/make-dmg.sh`, and uploads the DMG as a GitHub Release asset.

## Contributing

Bug reports and pull requests are welcome via GitHub Issues / PRs. The codebase has no external test runner (XCTest is unavailable in the CLT-only setup) — instead it ships an in-tree assertion runner (`swift run seemd-selftest`) that must stay green for any change.

## License

[MIT](LICENSE).
