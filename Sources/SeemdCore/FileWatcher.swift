import Foundation

/// Watches a file URL for write, rename, and delete events using
/// `DispatchSource.makeFileSystemObjectSource`.
///
/// Editors that save by replacing the file (write-to-temp + rename) are
/// handled: on a rename or delete event the watcher attempts to re-open the
/// original path and re-bind a fresh dispatch source.
public final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let watchQueue: DispatchQueue

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    /// Returns `nil` if the file cannot be opened at init time.
    public init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        self.watchQueue = DispatchQueue(label: "seemd.filewatcher", qos: .utility)
        guard self.bind() else { return nil }
    }

    /// Stop watching and release all resources.
    public func stop() {
        source?.cancel()
        source = nil
        closeFd()
    }

    // MARK: - Private

    @discardableResult
    private func bind() -> Bool {
        let rawFd = open(url.path, O_EVTONLY)
        guard rawFd >= 0 else { return false }
        fd = rawFd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: watchQueue
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.rename) || flags.contains(.delete) {
                // Editor replaced the file; tear down old source and re-bind.
                self.source?.cancel()
                self.source = nil
                self.closeFd()
                // Re-open after a short delay to let the replacement settle.
                self.watchQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.rebind()
                }
            }
            self.onChange()
        }

        src.setCancelHandler { [weak self] in
            self?.closeFd()
        }

        src.resume()
        source = src
        return true
    }

    private func rebind() {
        // Keep retrying briefly if the file hasn't appeared yet.
        if !bind() {
            watchQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.rebind()
            }
        }
    }

    private func closeFd() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }
}
