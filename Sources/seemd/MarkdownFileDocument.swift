import SwiftUI
import UniformTypeIdentifiers

/// Read-only document model backing `DocumentGroup(viewing:)`. Holds the
/// decoded Markdown text; macOS supplies native document tabs around it.
struct MarkdownFileDocument: FileDocument {

    /// Markdown, plain text, and `.text`. `.md`/`.markdown` conform to
    /// `public.plain-text`, so plain-text files open too.
    static var readableContentTypes: [UTType] {
        [UTType("net.daringfireball.markdown"), .plainText, .text].compactMap { $0 }
    }

    /// Viewer: nothing is ever written.
    static var writableContentTypes: [UTType] = []

    var text: String

    init(text: String = "") {
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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
