# seemd

A lightweight, native macOS Markdown **viewer** — VS Code-quality rendering with native performance.

> SwiftUI · `swift-markdown` parsing · native render · `Splash` syntax highlighting · macOS 14+

## Status

MVP (v0.1) in development. See [`PRD.md`](PRD.md) for the full product spec and [`prd.json`](prd.json) for tracked stories.

## Build

Requires Swift 5.9+ (Xcode or Command Line Tools).

```sh
swift build -c release
./scripts/bundle.sh        # produces seemd.app
open seemd.app
```

Run tests:

```sh
swift test
```

## Install (release `.dmg`)

Download the latest `.dmg` from [Releases](../../releases), open it, and drag **seemd** to Applications.

If macOS blocks the app because it is not notarized (ad-hoc build):

1. Right-click (or Control-click) **seemd.app**
2. Choose **Open**
3. Confirm **Open** in the dialog

This is only needed once.

## License

[MIT](LICENSE).
