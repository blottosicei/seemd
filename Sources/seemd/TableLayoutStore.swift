import SwiftUI

/// Per-window mutable layout state for resizable table columns.
///
/// This is intentionally SEPARATE from `RenderContext` (which is an immutable
/// `Equatable` value): column widths are user-driven, per-window layout that
/// must survive `LazyVStack` recycling (scrolling away/back) and tab switches.
/// Only `TableView` observes this object via `@EnvironmentObject` — it is a
/// leaf, so its own re-render on a width drag does not propagate up into
/// `BlockView`/`DocumentView`. Keys are derived from immutable table content
/// (column count + header plaintext + row count), so reading/writing here can
/// never create a scroll-spy / render feedback loop.
final class TableLayoutStore: ObservableObject {
    @Published var widths: [String: [CGFloat]] = [:]

    func widths(for key: String) -> [CGFloat]? {
        widths[key]
    }

    func setWidths(_ values: [CGFloat], for key: String) {
        widths[key] = values
    }
}
