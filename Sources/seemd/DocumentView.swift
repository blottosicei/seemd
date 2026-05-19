import SwiftUI
import SeemdCore

/// The scrollable rendered Markdown surface.
struct DocumentView: View {
    @ObservedObject var model: DocumentModel
    @FocusState private var searchFocused: Bool

    private var matchCount: Int {
        guard !model.searchQuery.isEmpty else { return 0 }
        return SearchEngine.matchCount(in: model.source, query: model.searchQuery)
    }

    var body: some View {
        documentScroll
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Find", text: $model.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .focused($searchFocused)
                        if !model.searchQuery.isEmpty {
                            Text("\(matchCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                model.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .seemdFocusSearch)) { _ in
                searchFocused = true
            }
    }

    private var documentScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.blocks.indices, id: \.self) { i in
                        BlockView(block: model.blocks[i], model: model)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .coordinateSpace(name: "docScroll")
            .background(Color(hex: model.palette.windowBackground, fallback: Color(NSColor.textBackgroundColor)))
            .onPreferenceChange(HeadingFramePreferenceKey.self) { frames in
                updateActiveHeading(frames)
            }
            .onChange(of: model.scrollTarget) {
                guard let target = model.scrollTarget else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                // Clear so the same target can be requested again later.
                DispatchQueue.main.async { model.scrollTarget = nil }
            }
        }
    }

    /// Scroll-spy: delegates to the pure `ScrollSpy.activeSlug` function in
    /// SeemdCore, using a 12-pt inset to match the previous threshold behaviour.
    private func updateActiveHeading(_ frames: [AppHeadingFrame]) {
        guard !frames.isEmpty else { return }
        let coreFrames = frames.map {
            HeadingFrame(slug: $0.slug, minY: Double($0.minY))
        }
        let candidate = ScrollSpy.activeSlug(
            headingFrames: coreFrames,
            viewportTopInset: 12
        )
        if let candidate, candidate != model.activeHeadingSlug {
            model.activeHeadingSlug = candidate
        }
    }
}
