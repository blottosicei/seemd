# seemd

A lightweight, native macOS Markdown **viewer** — VS Code-quality rendering with native performance.

> SwiftUI · `swift-markdown` parsing · native render · `Splash` syntax highlighting · macOS 14+

## Status

MVP (v0.1) in development. See [`PRD.md`](PRD.md) for the full product spec and [`prd.json`](prd.json) for tracked stories.

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

Because the release build is ad-hoc signed (not notarized), macOS may block it on first launch:

1. Right-click (or Control-click) **seemd.app** in Finder
2. Choose **Open**
3. Confirm **Open** in the dialog

This is only needed once.

## CI / Release workflow

- **CI** (`.github/workflows/ci.yml`): runs on every push and pull request — `swift build` + `swift run seemd-selftest`.
- **Release** (`.github/workflows/release.yml`): triggered by a `v*` tag — builds, self-tests, bundles, creates `dist/seemd.dmg` via `scripts/make-dmg.sh`, and uploads the DMG as a GitHub Release asset.

## License

[MIT](LICENSE).
