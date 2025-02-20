import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, about
    }

    @ObservedObject var menuState = MenuState.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info")
                }
                .tag(Tabs.about)
        }.padding(20)
    }
}

#Preview {
    SettingsView().environmentObject(SettingsStore.shared)
}
