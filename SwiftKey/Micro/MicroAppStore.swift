// Loads and watches the micro-apps folder (`micro/` next to the config file) and writes
// `micro-errors.log` next to the config file on each load.
import Foundation
import SwiftKeyCore

@MainActor
final class MicroAppStore {
    /// Larger files are reported, not read.
    nonisolated static let maxFileSize = MicroAppChecker.maxFileSize

    let folderURL: URL
    let logURL: URL
    private(set) var catalog = MicroAppCatalog()
    /// Called on each load of the folder, also the loads that the watch makes.
    var onLoad: (() -> Void)?

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingReload: DispatchWorkItem?
    private var onChange: ((_ previous: MicroAppCatalog, _ current: MicroAppCatalog) -> Void)?

    /// `micro/` and `micro-errors.log` next to the config file. With `SWIFTKEY_CONFIG` set, both get
    /// the config file name in front, like the other data files: `SWIFTKEY_CONFIG=/tmp/test.yaml`
    /// uses `/tmp/test.yaml.micro/` and `/tmp/test.yaml.micro-errors.log`, so two overrides in one
    /// directory never share a folder.
    init(configURL: URL, paths: AppPaths = .current) {
        folderURL = paths.microFolder(config: configURL)
        logURL = Self.logURL(configURL: configURL, paths: paths)
    }

    /// The error log of a config file's micro-apps.
    nonisolated static func logURL(configURL: URL, paths: AppPaths = .current) -> URL {
        if let override = paths.configOverride, override.standardizedFileURL == configURL.standardizedFileURL {
            return URL(fileURLWithPath: configURL.path + ".micro-errors.log")
        }
        return configURL.deletingLastPathComponent().appendingPathComponent("micro-errors.log")
    }

    /// `libs/` inside the micro-apps folder: the library files.
    var librariesURL: URL { folderURL.appendingPathComponent(MicroAppLibraries.folderName, isDirectory: true) }

    var displayPath: String { Self.display(folderURL) }
    var logDisplayPath: String { Self.display(logURL) }

    private static func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }

    /// Reads every `*.yaml` file of the folder. A missing folder gives an empty list, not an error.
    @discardableResult
    func load() -> MicroAppCatalog {
        onLoad?()
        let libraries = MicroAppLibraries.read(folder: librariesURL)
        catalog = MicroAppCatalog.build(hashed: readFiles(libraries: libraries))
        catalog.libraryIssues = MicroAppCatalog.checkLibraries(libraries)
        writeLog()
        return catalog
    }

    /// Loads again after every change in the folder, in its files, or when the folder appears
    /// or disappears. `onChange` gets the list before and after the change.
    func watch(onChange: @escaping (_ previous: MicroAppCatalog, _ current: MicroAppCatalog) -> Void) {
        self.onChange = onChange
        rewatch()
    }

    func stopWatching() {
        onChange = nil
        pendingReload?.cancel()
        sources.forEach { $0.cancel() }
        sources = []
    }

    // MARK: Private

    private func readFiles(libraries: MicroAppLibraries) -> [(file: String, result: Result<MicroApp, MicroAppFailure>, hash: String)] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        return names.filter(Self.isMicroAppFile).compactMap { name in
            let url = folderURL.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            func failure(_ message: String, hash: String = "") -> (String, Result<MicroApp, MicroAppFailure>, String) {
                (name, .failure(MicroAppFailure(issues: [MicroAppIssue(file: name, line: 1, message: message)])), hash)
            }
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > Self.maxFileSize { return failure(MicroAppChecker.tooLargeMessage) }
            do {
                let data = try Data(contentsOf: url)
                // The hash is of exactly the bytes that were checked, so an approval covers what runs.
                let hash = MicroAppApprovals.hash(data)
                guard let text = String(data: data, encoding: .utf8) else { return failure(MicroAppChecker.notUTF8Message, hash: hash) }
                return (name, MicroAppChecker.check(text, fileName: name, libraries: libraries), hash)
            } catch {
                return failure("cannot read the file: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func isMicroAppFile(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.hasSuffix("." + MicroAppChecker.fileExtension)
    }

    /// Written again on each load; empty when all files are good. Skipped when the config
    /// directory does not exist. An unchanged log is left alone: writing it would wake the
    /// directory watch and load again in a loop.
    private func writeLog() {
        let directory = logURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let data = Data(catalog.logText.utf8)
        if FileManager.default.fileExists(atPath: logURL.path), (try? Data(contentsOf: logURL)) == data { return }
        // In place: a log needs no atomic replace, and no rename event wakes the directory watch.
        try? data.write(to: logURL)
    }

    private func rewatch() {
        sources.forEach { $0.cancel() }
        sources = []
        guard onChange != nil else { return }
        // The config directory, for the folder appearing or disappearing.
        var paths = [folderURL.deletingLastPathComponent().path, folderURL.path]
        // Each file, for in-place saves that do not touch the folder.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) {
            paths += names.filter(Self.isMicroAppFile).map { folderURL.appendingPathComponent($0).path }
        }
        // The libraries folder and its files: a change of a library changes the micro-apps that use it.
        paths.append(librariesURL.path)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: librariesURL.path) {
            paths += names.filter(Self.isMicroAppFile).map { librariesURL.appendingPathComponent($0).path }
        }
        sources = paths.compactMap(makeSource)
    }

    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// Coalesces bursts of events from one save.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let onChange = self.onChange else { return }
                let previous = self.catalog
                let current = self.load()
                self.rewatch()
                if current != previous { onChange(previous, current) }
            }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
