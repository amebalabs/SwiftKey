import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, snippets, about
    }

    @State private var isGalleryWindowShown = false
    private var galleryWindow: NSWindow?

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)

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
        }.padding(20)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(ConfigManager())
}
