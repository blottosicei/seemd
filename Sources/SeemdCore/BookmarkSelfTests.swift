import Foundation

// Self-test cases for BookmarkStore (US-005).
// These tests use an isolated UserDefaults suite so they never pollute
// .standard, and write to a temp file so no real user files are needed.

public func bookmarkCases() -> [TestCase] {
    [
        TestCase("bookmark/save-and-resolve") { t in
            // Create a real temp file so URL(resolvingBookmarkData:) succeeds.
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tmpFile = tmpDir.appendingPathComponent("seemd-bm-test-\(UUID().uuidString).md")
            do {
                try "# test".write(to: tmpFile, atomically: true, encoding: .utf8)
            } catch {
                t.expect(false, "failed to create temp file: \(error)")
                return
            }
            defer { try? FileManager.default.removeItem(at: tmpFile) }

            let suiteName = "seemd.test.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "could not create isolated UserDefaults suite")
                return
            }
            defer { ud.removePersistentDomain(forName: suiteName) }

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
        },

        TestCase("bookmark/recentPaths-contains-saved") { t in
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tmpFile = tmpDir.appendingPathComponent("seemd-bm-recent-\(UUID().uuidString).md")
            do {
                try "# recent".write(to: tmpFile, atomically: true, encoding: .utf8)
            } catch {
                t.expect(false, "failed to create temp file: \(error)")
                return
            }
            defer { try? FileManager.default.removeItem(at: tmpFile) }

            let suiteName = "seemd.test.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "could not create isolated UserDefaults suite")
                return
            }
            defer { ud.removePersistentDomain(forName: suiteName) }

            let store = BookmarkStore(defaults: ud)
            do { try store.save(tmpFile) } catch {
                t.expect(false, "save threw: \(error)")
                return
            }

            let paths = store.recentPaths()
            t.expect(paths.contains(tmpFile.path), "recentPaths must contain saved path")
        },

        TestCase("bookmark/remove-drops-entry") { t in
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tmpFile = tmpDir.appendingPathComponent("seemd-bm-remove-\(UUID().uuidString).md")
            do {
                try "# remove".write(to: tmpFile, atomically: true, encoding: .utf8)
            } catch {
                t.expect(false, "failed to create temp file: \(error)")
                return
            }
            defer { try? FileManager.default.removeItem(at: tmpFile) }

            let suiteName = "seemd.test.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "could not create isolated UserDefaults suite")
                return
            }
            defer { ud.removePersistentDomain(forName: suiteName) }

            let store = BookmarkStore(defaults: ud)
            do { try store.save(tmpFile) } catch {
                t.expect(false, "save threw: \(error)")
                return
            }
            store.remove(tmpFile)

            let paths = store.recentPaths()
            t.expect(!paths.contains(tmpFile.path), "recentPaths must not contain removed path")
        },

        TestCase("bookmark/resolve-unknown-returns-nil") { t in
            let suiteName = "seemd.test.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "could not create isolated UserDefaults suite")
                return
            }
            defer { ud.removePersistentDomain(forName: suiteName) }

            let store = BookmarkStore(defaults: ud)
            let unknown = URL(fileURLWithPath: "/tmp/seemd-nonexistent-\(UUID().uuidString).md")
            let result = store.resolve(unknown)
            t.expect(result == nil, "resolve of unknown URL must return nil")
        }
    ]
}
