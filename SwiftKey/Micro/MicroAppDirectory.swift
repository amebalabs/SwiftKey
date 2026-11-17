import Combine
import Foundation
import SwiftKeyCore

/// The loaded micro-apps for Settings: the config editor's micro-app picker reads them.
/// The app delegate updates it each time the micro-apps folder loads.
final class MicroAppDirectory: ObservableObject {
    @Published private(set) var catalog = MicroAppCatalog()
    /// The micro-apps folder of the current config; nil before the first load.
    @Published private(set) var folderURL: URL?

    func update(_ catalog: MicroAppCatalog, folder: URL?) {
        if self.catalog != catalog { self.catalog = catalog }
        if folderURL != folder { folderURL = folder }
    }

    /// The picker entries for a `micro://` item whose id is `current`.
    func choices(current: String?) -> [MicroAppChoice] {
        catalog.bindingChoices(current: current)
    }

    /// The file of the micro-app with `id`, working or broken; nil when no file has it.
    func fileURL(for id: String) -> URL? {
        guard let folderURL else { return nil }
        switch catalog.resolve(id) {
        case .working(_, let entry), .broken(let entry):
            return folderURL.appendingPathComponent(entry.file)
        case .missing:
            return nil
        }
    }

    /// Why the micro-app with `id` does not work, in one line; nil when it works or `id` is empty.
    func problem(for id: String) -> String? {
        guard !id.isEmpty else { return nil }
        let folder = folderURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "the micro-apps folder"
        return catalog.resolve(id).problem(id: id, folder: folder)
    }
}
