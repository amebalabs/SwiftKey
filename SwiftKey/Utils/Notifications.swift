import Foundation

extension Notification.Name {
    static let hideOverlay = Notification.Name("hideOverlay")
    static let presentOverlay = Notification.Name("presentOverlay")
    static let presentGalleryWindow = Notification.Name("presentGalleryWindow")
    static let openLauncha = Notification.Name("openLauncha")
    static let showAccessibilityHelp = Notification.Name("showAccessibilityHelp")
    static let resetMenuState = Notification.Name("ResetMenuState")
    static let menuIconUpdated = Notification.Name("menuIconUpdated")
}

/// Keys of the `userInfo` of `.presentOverlay`.
enum PresentOverlayKey {
    /// `false` when the menu must not run the command of a lone `dynamic://` item on its own,
    /// as when a deep link opened it. Missing means `true`.
    static let loadsDynamicMenu = "loadsDynamicMenu"
}
