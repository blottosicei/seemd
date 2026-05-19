import SwiftUI
import UniformTypeIdentifiers
import SeemdCore

/// Shown when a window has no open document: open button, drop target, and
/// the macOS recent-documents list.
struct EmptyStateView: View {
    @ObservedObject var model: DocumentModel
    @State private var recents: [URL] = []
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("seemd")
                    .font(.title.weight(.semibold))
                Text("A quiet Markdown viewer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Open File…") { openPanel() }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

            Text("or drop a .md file here")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            if !recents.isEmpty {
                recentList
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear,
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
                .padding(16)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear { recents = Self.recentURLs() }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(recents.prefix(8), id: \.self) { url in
                Button {
                    model.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .help(url.path)
            }
        }
        .frame(maxWidth: 320)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private static func recentURLs() -> [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.plainText]
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { model.open(url) }
        }
        return true
    }
}
