import Foundation

/// `swiftkey-micro check <file.yaml> [more files]`: checks micro-app files without a running SwiftKey.
///
/// Pure logic: the arguments and a file reader go in; the lines for standard output and standard
/// error and the exit code come out. The app target only reads the files and prints.
public enum MicroAppCheckCommand {
    public static let option = "check"
    public static let usage = "usage: swiftkey-micro check [--libs DIR] <file.yaml> [more files]"

    /// Every given file is good.
    public static let exitOK: Int32 = 0
    /// At least one file has a problem.
    public static let exitProblems: Int32 = 1
    /// A wrong call: no file, a file that cannot be read, a name that does not end in `.yaml`.
    public static let exitUsage: Int32 = 2

    public struct Outcome: Equatable, Sendable {
        /// Lines for standard output, without line ends.
        public var output: [String]
        /// Lines for standard error, without line ends.
        public var errors: [String]
        public var exitCode: Int32

        public init(output: [String], errors: [String], exitCode: Int32) {
            self.output = output
            self.errors = errors
            self.exitCode = exitCode
        }
    }

    /// `arguments` are the process arguments without the program name. True when they ask for the check.
    public static func handles(_ arguments: [String]) -> Bool {
        arguments.first == option
    }

    /// Checks the files named after `check`. `read` returns the bytes of a path or throws when
    /// it cannot read it. The id rules of the micro-apps folder apply to the given files only: of
    /// two files with the same id, the later one by path has the duplicate id problem.
    ///
    /// Each problem is a `file:line: message` line with the message of the micro-app error log,
    /// sorted by file and line; a good file gives `<file>: ok`. The location is the path as given;
    /// a duplicate id message names the other file by its file name, as the error log does.
    /// `libraries` gives the libraries for a file path: `libs/` next to that file. A file inside a
    /// folder named `libs` is checked as a library.
    public static func run(_ arguments: [String], read: (String) throws -> Data,
                           libraries: (String) -> MicroAppLibraries = { _ in MicroAppLibraries() }) -> Outcome {
        var files = arguments
        if files.first == option { files.removeFirst() }
        guard !files.isEmpty else {
            return Outcome(output: [], errors: ["swiftkey-micro check: no file given", usage], exitCode: exitUsage)
        }

        var errors: [String] = []
        var checked: [(file: String, result: Result<MicroApp, MicroAppFailure>)] = []
        var libraryLines: [String] = []
        var libraryProblems = false
        for path in files {
            guard path.hasSuffix("." + MicroAppChecker.fileExtension) else {
                errors.append("\(path): the name does not end in .\(MicroAppChecker.fileExtension)")
                continue
            }
            let data: Data
            do {
                data = try read(path)
            } catch {
                errors.append("\(path): cannot read the file: \(error.localizedDescription)")
                continue
            }
            if isLibraryPath(path) {
                let issues = checkLibrary(data, path: path, libraries: libraries(path))
                libraryProblems = libraryProblems || !issues.isEmpty
                libraryLines += issues.isEmpty ? ["\(path): ok"] : issues.map { "\(path):\($0.line): \(MicroAppCatalog.logMessage($0.message))" }
                continue
            }
            checked.append((path, check(data, path: path, libraries: libraries(path))))
        }
        if !errors.isEmpty {
            return Outcome(output: [], errors: errors + [usage], exitCode: exitUsage)
        }

        let catalog = MicroAppCatalog.build(checked) { ($0 as NSString).lastPathComponent }
        var output: [String] = []
        for entry in catalog.entries {
            if entry.issues.isEmpty {
                output.append("\(entry.file): ok")
            } else {
                output += entry.issues.map { "\(entry.file):\($0.line): \(MicroAppCatalog.logMessage($0.message))" }
            }
        }
        output += libraryLines
        return Outcome(output: output, errors: [], exitCode: catalog.issues.isEmpty && !libraryProblems ? exitOK : exitProblems)
    }

    /// `true` for a file in a folder named `libs`.
    public static func isLibraryPath(_ path: String) -> Bool {
        ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent == MicroAppLibraries.folderName
    }

    /// The `libs` folder for a file: the folder of a library, else `libs/` next to the micro-app.
    public static func libraryFolder(for path: String) -> URL {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        return isLibraryPath(path) ? directory : directory.appendingPathComponent(MicroAppLibraries.folderName, isDirectory: true)
    }

    private static func checkLibrary(_ data: Data, path: String, libraries: MicroAppLibraries) -> [MicroAppIssue] {
        if data.count > MicroAppChecker.maxFileSize { return [MicroAppIssue(file: path, line: 1, message: MicroAppChecker.tooLargeMessage)] }
        guard let text = String(data: data, encoding: .utf8) else { return [MicroAppIssue(file: path, line: 1, message: MicroAppChecker.notUTF8Message)] }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let source = MicroAppLibrarySource(name: name, file: MicroAppLibraries.file(for: name), text: text)
        if case .failure(let failure) = MicroAppChecker.checkLibrary(source, libraries: libraries, stack: []) { return failure.issues }
        return []
    }

    /// The same checks as the micro-apps folder: size, UTF-8, then the checker.
    private static func check(_ data: Data, path: String, libraries: MicroAppLibraries) -> Result<MicroApp, MicroAppFailure> {
        func failure(_ message: String) -> Result<MicroApp, MicroAppFailure> {
            .failure(MicroAppFailure(issues: [MicroAppIssue(file: (path as NSString).lastPathComponent, line: 1, message: message)]))
        }
        if data.count > MicroAppChecker.maxFileSize { return failure(MicroAppChecker.tooLargeMessage) }
        guard let text = String(data: data, encoding: .utf8) else { return failure(MicroAppChecker.notUTF8Message) }
        return MicroAppChecker.check(text, fileName: path, libraries: libraries)
    }
}
