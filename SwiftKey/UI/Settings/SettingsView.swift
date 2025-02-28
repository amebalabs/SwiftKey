import SwiftUI
import Combine

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, menuConfig, about
    }
    
    @StateObject private var configManager = ConfigManager.shared
    @State private var menuConfig: [MenuItem] = []
    @State private var selectedTab: Tabs = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            
            MenuConfigView(config: $menuConfig)
                .tabItem {
                    Label("Menu Editor", systemImage: "list.bullet.indent")
                }
                .tag(Tabs.menuConfig)
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info")
                }
                .tag(Tabs.about)
        }
        .padding(20)
        .frame(minWidth: 800, minHeight: 600)
        .environmentObject(configManager)
        .onAppear {
            // Load the menu configuration
            self.menuConfig = configManager.menuItems
            
            // Set up a publisher to update our config when it changes
            configManager.menuItemsPublisher
                .sink { items in
                    self.menuConfig = items
                }
                .store(in: &cancellables)
                
            // Listen for notification to switch to Menu Editor tab
            NotificationCenter.default.publisher(for: .switchToMenuEditor)
                .sink { _ in
                    self.selectedTab = .menuConfig
                }
                .store(in: &cancellables)
        }
    }
    
    // Store cancellables for Combine subscriptions
    @State private var cancellables = Set<AnyCancellable>()
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
