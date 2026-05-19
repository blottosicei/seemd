import SwiftUI

/// The Edit-mode formatting bar. Each button posts a `.seemdFormat`
/// notification carrying a `FormatAction`; the focused `MarkdownEditor`
/// coordinator performs it through the native text system (so Undo works).
/// Rendered as a `ToolbarItemGroup` so it sits in the unified title bar only
/// while editing.
struct FormattingButtons: View {
    var body: some View {
        HStack(spacing: 2) {
            group(.bold, "bold", "Bold")
            group(.italic, "italic", "Italic")
            group(.underline, "underline", "Underline")
            Divider().frame(height: 16)
            group(.h1, "1.square", "Heading 1")
            group(.h2, "2.square", "Heading 2")
            group(.h3, "3.square", "Heading 3")
            Divider().frame(height: 16)
            group(.quote, "text.quote", "Blockquote")
            group(.bullet, "list.bullet", "Bullet list")
            group(.numbered, "list.number", "Numbered list")
            group(.task, "checklist", "Task list")
            Divider().frame(height: 16)
            group(.inlineCode, "chevron.left.forwardslash.chevron.right",
                  "Inline code")
            group(.codeBlock, "curlybraces.square", "Code block")
            group(.link, "link", "Link")
        }
    }

    private func group(_ action: FormatAction, _ symbol: String,
                       _ help: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .seemdFormat,
                                            object: action)
        } label: {
            Image(systemName: symbol)
        }
        .help(help)
    }
}
