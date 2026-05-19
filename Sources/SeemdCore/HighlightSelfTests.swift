import Foundation

/// Self-test cases for SyntaxHighlighter (US-004).
/// All cases are synchronous-callable; async highlight() is bridged via
/// DispatchSemaphore + Task so the existing TestCase infrastructure is unchanged.
public func highlightCases() -> [TestCase] {
    [
        TestCase("highlight/swift-returns-non-empty-tokens") { t in
            let tokens = runHighlight("let x = 1", language: "swift", theme: .light)
            t.expect(!tokens.isEmpty, "expected non-empty tokens for Swift code")
        },

        TestCase("highlight/concatenated-text-reproduces-input") { t in
            let input = "let x = 1"
            let tokens = runHighlight(input, language: "swift", theme: .light)
            let joined = tokens.map(\.text).joined()
            t.expectEqual(joined, input, "concatenated token text must equal original input")
        },

        TestCase("highlight/light-theme-returns-tokens") { t in
            let tokens = runHighlight("let x = 1", language: "swift", theme: .light)
            t.expect(!tokens.isEmpty, "light theme must return tokens")
        },

        TestCase("highlight/dark-theme-returns-tokens") { t in
            let tokens = runHighlight("let x = 1", language: "swift", theme: .dark)
            t.expect(!tokens.isEmpty, "dark theme must return tokens")
        },

        TestCase("highlight/palette-is-dark") { t in
            let result = runPaletteIsDark(.dark)
            t.expect(result, "paletteIsDark(.dark) must return true")
        },

        TestCase("highlight/palette-is-not-dark-for-light") { t in
            let result = runPaletteIsDark(.light)
            t.expect(!result, "paletteIsDark(.light) must return false")
        },

        // Language alias normalisation — each alias must produce at least one token
        TestCase("highlight/alias-js") { t in
            let tokens = runHighlight("var x = 1;", language: "js", theme: .light)
            t.expect(!tokens.isEmpty, "js alias must return tokens")
        },
        TestCase("highlight/alias-javascript") { t in
            let tokens = runHighlight("var x = 1;", language: "javascript", theme: .light)
            t.expect(!tokens.isEmpty, "javascript alias must return tokens")
        },
        TestCase("highlight/alias-ts") { t in
            let tokens = runHighlight("const x: number = 1;", language: "ts", theme: .light)
            t.expect(!tokens.isEmpty, "ts alias must return tokens")
        },
        TestCase("highlight/alias-typescript") { t in
            let tokens = runHighlight("const x: number = 1;", language: "typescript", theme: .light)
            t.expect(!tokens.isEmpty, "typescript alias must return tokens")
        },
        TestCase("highlight/alias-py") { t in
            let tokens = runHighlight("x = 1", language: "py", theme: .light)
            t.expect(!tokens.isEmpty, "py alias must return tokens")
        },
        TestCase("highlight/alias-python") { t in
            let tokens = runHighlight("x = 1", language: "python", theme: .light)
            t.expect(!tokens.isEmpty, "python alias must return tokens")
        },
        TestCase("highlight/alias-json") { t in
            let tokens = runHighlight("{\"key\": 1}", language: "json", theme: .light)
            t.expect(!tokens.isEmpty, "json alias must return tokens")
        },
        TestCase("highlight/alias-sh") { t in
            let tokens = runHighlight("echo hello", language: "sh", theme: .light)
            t.expect(!tokens.isEmpty, "sh alias must return tokens")
        },
        TestCase("highlight/alias-shell") { t in
            let tokens = runHighlight("echo hello", language: "shell", theme: .light)
            t.expect(!tokens.isEmpty, "shell alias must return tokens")
        },
        TestCase("highlight/alias-bash") { t in
            let tokens = runHighlight("echo hello", language: "bash", theme: .light)
            t.expect(!tokens.isEmpty, "bash alias must return tokens")
        },

        TestCase("highlight/unknown-language-plain-token") { t in
            let input = "some code"
            let tokens = runHighlight(input, language: "cobol", theme: .light)
            t.expect(!tokens.isEmpty, "unknown language must still return a token")
            let joined = tokens.map(\.text).joined()
            t.expectEqual(joined, input, "unknown language token text must equal input")
        },

        TestCase("highlight/nil-language-plain-token") { t in
            let input = "some code"
            let tokens = runHighlight(input, language: nil, theme: .light)
            t.expect(!tokens.isEmpty, "nil language must still return a token")
            let joined = tokens.map(\.text).joined()
            t.expectEqual(joined, input, "nil language token text must equal input")
        },
    ]
}

// MARK: - Synchronous bridge helpers

/// Runs `SyntaxHighlighter.highlight` synchronously via a semaphore+Task bridge.
private func runHighlight(_ code: String, language: String?, theme: CodeTheme) -> [HighlightToken] {
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: [HighlightToken] = []
    let highlighter = SyntaxHighlighter()
    Task {
        result = await highlighter.highlight(code, language: language, theme: theme)
        sema.signal()
    }
    sema.wait()
    return result
}

/// Runs `SyntaxHighlighter.paletteIsDark` synchronously.
private func runPaletteIsDark(_ theme: CodeTheme) -> Bool {
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result = false
    let highlighter = SyntaxHighlighter()
    Task {
        result = await highlighter.paletteIsDark(theme)
        sema.signal()
    }
    sema.wait()
    return result
}
