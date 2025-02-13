import SwiftUI

class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    public enum OverlayStyle: String, CaseIterable {
        case panel = "Default"
        case hud = "Compact: HUD"
        case faceless = "Compact: Menu Bar"
    }

    @AppStorage("IsShowingMenuBar") public var isShowingMenuBar: Bool = true
    @AppStorage("ConfigDirectoryPath") public var configDirectoryPath: String = ""
    @AppStorage("menuStateResetDelay") public var menuStateResetDelay: Double = 3.0
    @AppStorage("useHorizontalOverlayLayout") public var useHorizontalOverlayLayout: Bool = false
    @AppStorage("overlayStyle") public var overlayStyle: OverlayStyle = .hud

    var facelessMode: Bool {
        overlayStyle == .faceless
    }

    var configDirectoryResolvedURL: URL? {
        guard let path = configDirectoryPath as NSString? else { return nil }
        return URL(fileURLWithPath: path.expandingTildeInPath).resolvingSymlinksInPath()
    }

    var configDirectoryResolvedPath: String? {
        configDirectoryResolvedURL?.path
    }
}
