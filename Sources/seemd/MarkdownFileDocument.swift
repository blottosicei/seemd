import SwiftUI
import UniformTypeIdentifiers

/// Editable document model backing `DocumentGroup(newDocument:)`. Holds the
/// decoded Markdown text; macOS supplies native document tabs, the dirty
/// indicator, the close-confirmation sheet, Save (⌘S) and Undo (⌘Z) around it.
struct MarkdownFileDocument: FileDocument {

    /// Markdown, plain text, and `.text`. `.md`/`.markdown` conform to
    /// `public.plain-text`, so plain-text files open too.
    static var readableContentTypes: [UTType] {
        [UTType("net.daringfireball.markdown"), .plainText, .text].compactMap { $0 }
    }

    /// Same set as readable so existing Markdown / text files round-trip on
    /// Save without a format conversion prompt.
    static var writableContentTypes: [UTType] {
        [UTType("net.daringfireball.markdown"), .plainText, .text].compactMap { $0 }
    }

    var text: String

    /// New (untitled) document — used by the `New` command.
    init() {
        self.text = ""
    }

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = decoded
    }

    /// Write the current text back as UTF-8. This is the path Save (⌘S) and
    /// the close-confirmation "Save" reach; mutating `text` via the editor
    /// binding marks the window dirty and routes here.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
