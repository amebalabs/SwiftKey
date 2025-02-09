import SwiftUI

class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()
    
    @AppStorage("IsShowingMenuBar") public var isShowingMenuBar: Bool = true
    @AppStorage("ConfigDirectoryPath") public var configDirectoryPath: String = ""
    @AppStorage("facelessMode") public var facelessMode: Bool = true
    @AppStorage("menuStateResetDelay") public var menuStateResetDelay: Double = 3.0
    @AppStorage("useHorizontalOverlayLayout") public var useHorizontalOverlayLayout: Bool = false
    
    var configDirectoryResolvedURL: URL? {
        guard let path = configDirectoryPath as NSString? else { return nil }
        return URL(fileURLWithPath: path.expandingTildeInPath).resolvingSymlinksInPath()
    }
    
    var configDirectoryResolvedPath: String? {
        configDirectoryResolvedURL?.path
    }
}
