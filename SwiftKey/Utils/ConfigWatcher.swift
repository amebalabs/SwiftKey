import AppKit

class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: CInt

    init?(url: URL, reloadHandler: @escaping () -> Void) {
        guard let path = url.path.cString(using: .utf8) else { return nil }
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor < 0 { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        source?.setEventHandler(handler: reloadHandler)
        source?.setCancelHandler { close(self.fileDescriptor) }
        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}
