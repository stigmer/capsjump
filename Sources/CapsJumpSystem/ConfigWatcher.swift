// Calls back within about 100 ms of any change to the config file: an edit in place, an
// editor's save-by-replace, a delete, or the file appearing later. FSEvents watches the
// file's own path (and, for a symlinked file, the file it points to), so nothing else on
// the disk wakes the app.

import CoreServices
import Foundation

@MainActor
public final class ConfigWatcher {
    private let paths: [String]
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?

    public init(file: URL, onChange: @escaping @MainActor () -> Void) {
        let resolved = file.resolvingSymlinksInPath().path
        paths = resolved == file.path ? [file.path] : [file.path, resolved]
        self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            configWatcherCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            FSEventStreamCreateFlags(flags)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    fileprivate func changed() {
        onChange()
    }
}

private func configWatcherCallback(
    stream: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    count: Int,
    paths: UnsafeMutableRawPointer,
    flags: UnsafePointer<FSEventStreamEventFlags>,
    ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    // The stream is scheduled on the main queue, so the watcher never leaves it.
    nonisolated(unsafe) let watcher = info
    MainActor.assumeIsolated {
        Unmanaged<ConfigWatcher>.fromOpaque(watcher).takeUnretainedValue().changed()
    }
}
