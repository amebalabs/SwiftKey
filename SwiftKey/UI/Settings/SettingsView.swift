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

            SnippetsSettingsView(openGallery: {
                Task {
                    await AppDelegate.showGalleryWindow()
                }
            })
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

struct SnippetsSettingsView: View {
    let openGallery: () -> Void
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Snippets Gallery")
                .font(.headline)

            Text("Browse and install shared configuration snippets from the SwiftKey community.")
                .lineLimit(nil)

            Button("Open Snippets Gallery") {
                openGallery()
            }
            .controlSize(.large)

            Divider()

            Text("Share Your Snippets")
                .font(.headline)

            Text(
                "Got a useful configuration? Share it with the community by submitting a pull request to the snippets repository."
            )
            .lineLimit(nil)

            Link(
                "Learn How to Share Snippets",
                destination: URL(string: "https://github.com/amebalabs/swiftkey-snippets")!
            )
            .padding(.top, 5)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(ConfigManager.shared)
}
