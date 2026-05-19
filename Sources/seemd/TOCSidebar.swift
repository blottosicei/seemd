import SwiftUI
import SeemdCore

/// Table-of-contents sidebar: indented headings with scroll-spy highlight.
struct TOCSidebar: View {
    @ObservedObject var model: DocumentModel

    private var accent: Color { Color(hex: model.palette.accentLink, fallback: .accentColor) }
    private var secondary: Color { Color(hex: model.palette.secondaryText, fallback: .secondary) }
    private var bodyColor: Color { Color(hex: model.palette.bodyText, fallback: .primary) }

    var body: some View {
        Group {
            if model.headings.isEmpty {
                VStack {
                    Spacer()
                    Text("No headings")
                        .font(.callout)
                        .foregroundStyle(secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(model.headings, id: \.slug, selection: Binding(
                    get: { model.activeHeadingSlug },
                    set: { if let s = $0 { select(s) } }
                )) { heading in
                    row(heading)
                        .tag(heading.slug)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Contents")
    }

    @ViewBuilder
    private func row(_ heading: MarkdownDocument.Heading) -> some View {
        let isActive = heading.slug == model.activeHeadingSlug
        HStack(spacing: 6) {
            Rectangle()
                .fill(isActive ? accent : Color.clear)
                .frame(width: 2)
            Text(heading.text)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? bodyColor : secondary)
                .lineLimit(2)
                .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { select(heading.slug) }
    }

    private func select(_ slug: String) {
        model.activeHeadingSlug = slug
        model.scrollTarget = slug
    }
}
