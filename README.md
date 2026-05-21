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

## CI / Release workflow

- **CI** (`.github/workflows/ci.yml`): runs on every push and pull request — `swift build` + `swift run seemd-selftest`.
- **Release** (`.github/workflows/release.yml`): triggered by a `v*` tag — builds, self-tests, bundles, creates `dist/seemd.dmg` via `scripts/make-dmg.sh`, and uploads the DMG as a GitHub Release asset.

## Contributing

Bug reports and pull requests are welcome via GitHub Issues / PRs. The codebase has no external test runner (XCTest is unavailable in the CLT-only setup) — instead it ships an in-tree assertion runner (`swift run seemd-selftest`) that must stay green for any change.

## License

[MIT](LICENSE).
