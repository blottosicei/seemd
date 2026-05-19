import Foundation

/// Pure search logic — no UI dependencies.
public enum SearchEngine {

    /// Returns all non-overlapping ranges of `query` inside `text`,
    /// using case-insensitive comparison. Returns `[]` for empty query.
    public static func matches(in text: String, query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var results: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: query,
                                     options: .caseInsensitive,
                                     range: searchStart..<text.endIndex) {
            results.append(range)
            searchStart = range.upperBound
        }
        return results
    }

    /// Convenience wrapper returning the count of matches.
    public static func matchCount(in text: String, query: String) -> Int {
        matches(in: text, query: query).count
    }
}
