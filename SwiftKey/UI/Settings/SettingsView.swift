import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, configEditor, snippets, about
        
        var idealSize: CGSize {
            switch self {
            case .general, .snippets, .about:
                return CGSize(width: 460, height: 500)
            case .configEditor:
                return CGSize(width: 940, height: 700)
            }
        }
    }

    @State private var selectedTab: Tabs = .general
    @State private var isGalleryWindowShown = false
    private var galleryWindow: NSWindow?

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)

            ConfigEditorSettingsView()
                .tabItem {
                    Label("Config Editor", systemImage: "list.bullet.rectangle")
                }
                .tag(Tabs.configEditor)

            SnippetsSettingsView()
                .tabItem {
                    Label("Snippets", systemImage: "square.grid.2x2")
                }
                .tag(Tabs.snippets)

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info")
                }
                .tag(Tabs.about)
        }
        .padding(20)
        .frame(
            idealWidth: selectedTab.idealSize.width,
            idealHeight: selectedTab.idealSize.height
        )
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(ConfigManager())
}
