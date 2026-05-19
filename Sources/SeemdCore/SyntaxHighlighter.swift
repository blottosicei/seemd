import Foundation
import Splash

// MARK: - Public types

public enum CodeTheme {
    case light, dark
}

public struct HighlightToken {
    public let text: String
    public let kind: String

    public init(text: String, kind: String) {
        self.text = text
        self.kind = kind
    }
}

// MARK: - Token-collecting OutputFormat / OutputBuilder

private struct TokenCollectorFormat: OutputFormat {
    func makeBuilder() -> TokenCollectorBuilder {
        TokenCollectorBuilder()
    }
}

private struct TokenCollectorBuilder: OutputBuilder {
    typealias Output = [HighlightToken]

    private var tokens: [HighlightToken] = []

    mutating func addToken(_ token: String, ofType type: TokenType) {
        tokens.append(HighlightToken(text: token, kind: type.string))
    }

    mutating func addPlainText(_ text: String) {
        tokens.append(HighlightToken(text: text, kind: "plain"))
    }

    mutating func addWhitespace(_ whitespace: String) {
        tokens.append(HighlightToken(text: whitespace, kind: "plain"))
    }

    mutating func build() -> [HighlightToken] {
        tokens
    }
}

// MARK: - Language alias normalisation

private func normaliseLanguage(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "swift":                         return "swift"
    case "js", "javascript":             return "javascript"
    case "ts", "typescript":             return "typescript"
    case "python", "py":                 return "python"
    case "json":                          return "json"
    case "sh", "shell", "bash":          return "shell"
    default:                              return "plain"
    }
}

// MARK: - SyntaxHighlighter actor

/// Actor-based syntax highlighter. Splash only supports Swift grammar natively;
/// for other languages a single plain token covering the full input is returned.
///
/// Dark base colour: approximately #1E1E1E (VS Code dark background).
public actor SyntaxHighlighter {

    public init() {}

    /// Highlight `code` and return a token array whose concatenated `.text`
    /// values reproduce the original input exactly.
    public func highlight(_ code: String, language: String?, theme: CodeTheme) -> [HighlightToken] {
        let lang = normaliseLanguage(language)

        if lang == "swift" {
            let format = TokenCollectorFormat()
            let highlighter = Splash.SyntaxHighlighter(format: format, grammar: SwiftGrammar())
            let tokens = highlighter.highlight(code)
            // Guard against empty result — fall through to plain
            if !tokens.isEmpty {
                return tokens
            }
        }

        // Non-swift languages or empty Swift result: one plain token
        return [HighlightToken(text: code, kind: "plain")]
    }

    /// Returns `true` when the theme is dark.
    /// Dark mode base background is approximately #1E1E1E.
    public func paletteIsDark(_ t: CodeTheme) -> Bool {
        t == .dark
    }
}
