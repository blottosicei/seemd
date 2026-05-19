import Foundation

// Self-test cases for BookmarkStore (US-005).
// These tests use an isolated UserDefaults suite so they never pollute
// .standard, and write to a temp file so no real user files are needed.

/// Runs `body` with a fresh, isolated UserDefaults suite that is torn down
/// afterwards (so cases never pollute `.standard`).
private func withIsolatedDefaults(_ t: TestContext,
                                  _ body: (UserDefaults) -> Void) {
    let suiteName = "seemd.test.\(UUID().uuidString)"
    guard let ud = UserDefaults(suiteName: suiteName) else {
        t.expect(false, "could not create isolated UserDefaults suite")
        return
    }
    defer { ud.removePersistentDomain(forName: suiteName) }
    body(ud)
}

/// Creates a real temp `.md` file (needed for `URL(resolvingBookmarkData:)`
/// to succeed), passes it to `body`, then removes it.
private func withTempMarkdownFile(_ t: TestContext,
                                  contents: String,
                                  _ body: (URL) -> Void) {
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let tmpFile = tmpDir.appendingPathComponent("seemd-bm-test-\(UUID().uuidString).md")
    do {
        try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
    } catch {
        t.expect(false, "failed to create temp file: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: tmpFile) }
    body(tmpFile)
}

public func bookmarkCases() -> [TestCase] {
    [
        TestCase("bookmark/save-and-resolve") { t in
            withTempMarkdownFile(t, contents: "# test") { tmpFile in
                withIsolatedDefaults(t) { ud in
                    let store = BookmarkStore(defaults: ud)
                    do {
                        try store.save(tmpFile)
                    } catch {
                        t.expect(false, "save threw: \(error)")
                        return
                    }
                    guard let resolved = store.resolve(tmpFile) else {
                        t.expect(false, "resolve returned nil")
                        return
                    }
                    t.expectEqual(
                        resolved.standardizedFileURL.path,
                        tmpFile.standardizedFileURL.path,
                        "resolved URL must point to the same file"
                    )
                }
            }
        },

        TestCase("bookmark/recentPaths-contains-saved") { t in
            withTempMarkdownFile(t, contents: "# recent") { tmpFile in
                withIsolatedDefaults(t) { ud in
                    let store = BookmarkStore(defaults: ud)
                    do { try store.save(tmpFile) } catch {
                        t.expect(false, "save threw: \(error)")
                        return
                    }
                    t.expect(store.recentPaths().contains(tmpFile.path),
                             "recentPaths must contain saved path")
                }
            }
        },

        TestCase("bookmark/remove-drops-entry") { t in
            withTempMarkdownFile(t, contents: "# remove") { tmpFile in
                withIsolatedDefaults(t) { ud in
                    let store = BookmarkStore(defaults: ud)
                    do { try store.save(tmpFile) } catch {
                        t.expect(false, "save threw: \(error)")
                        return
                    }
                    store.remove(tmpFile)
                    t.expect(!store.recentPaths().contains(tmpFile.path),
                             "recentPaths must not contain removed path")
                }
            }
        },

        TestCase("bookmark/resolve-unknown-returns-nil") { t in
            withIsolatedDefaults(t) { ud in
                let store = BookmarkStore(defaults: ud)
                let unknown = URL(fileURLWithPath: "/tmp/seemd-nonexistent-\(UUID().uuidString).md")
                t.expect(store.resolve(unknown) == nil,
                         "resolve of unknown URL must return nil")
            }
        }
    ]
}
