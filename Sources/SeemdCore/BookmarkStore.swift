import Foundation

/// Persists security-scoped bookmark data for recently opened files.
///
/// Bookmark data is stored in UserDefaults under the key "seemd.bookmarks"
/// as a [String: Data] dictionary keyed by absolute file path.
///
/// Security-scoped bookmark creation is attempted first (required for sandboxed
/// apps to re-access user-chosen files across launches). If the process is not
/// sandboxed (e.g., CLT / test environment) and `.withSecurityScope` throws,
/// the implementation falls back to a plain bookmark so the round-trip remains
/// testable without a sandbox entitlement.
public struct BookmarkStore {

    private let defaults: UserDefaults
    private static let key = "seemd.bookmarks"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Persistence helpers

    private func load() -> [String: Data] {
        defaults.dictionary(forKey: Self.key) as? [String: Data] ?? [:]
    }

    private func save(map: [String: Data]) {
        defaults.set(map, forKey: Self.key)
    }

    // MARK: - Public API

    /// Saves a bookmark for `url`.
    ///
    /// Tries security-scoped creation first; falls back to a plain bookmark
    /// so the round-trip works outside a sandbox (CLT / tests).
    public func save(_ url: URL) throws {
        let data: Data
        do {
            data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Not sandboxed or security scope unavailable — use a plain bookmark.
            data = try url.bookmarkData()
        }
        var map = load()
        map[url.path] = data
        save(map: map)
    }

    /// Resolves a stored bookmark for `url`, returning the resolved URL or nil.
    public func resolve(_ url: URL) -> URL? {
        guard let data = load()[url.path] else { return nil }
        var stale = false
        // Try resolving with security scope first; fall back to no options.
        if let resolved = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return resolved
        }
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    /// Returns the absolute paths of all bookmarked files.
    public func recentPaths() -> [String] {
        Array(load().keys)
    }

    /// Removes the stored bookmark for `url`.
    public func remove(_ url: URL) {
        var map = load()
        map.removeValue(forKey: url.path)
        save(map: map)
    }

    // MARK: - Security scope access

    /// Starts accessing the security-scoped resource at `url`.
    ///
    /// Returns `true` if access was granted; returns `false` (no-op) when the
    /// URL is not security-scoped (e.g., in tests / non-sandboxed processes).
    @discardableResult
    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// Stops accessing the security-scoped resource at `url`.
    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
