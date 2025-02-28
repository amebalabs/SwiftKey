import SwiftUI
import Yams
import UniformTypeIdentifiers
import AppKit

// Sample data for testing and previews.
extension MenuItem {
    static func sampleData() -> [MenuItem] {
        return [
            MenuItem(
                key: "a",
                icon: "star.fill",
                title: "Launch Calculator",
                action: "launch://Calculator",
                submenu: [
                    MenuItem(
                        key: "b",
                        icon: "safari",
                        title: "Open Website",
                        action: "open://https://www.example.com",
                        submenu: nil
                    ),
                ]
            ),
            MenuItem(
                key: "c",
                icon: "printer",
                title: "Print Message",
                action: "shell://echo 'Hello, World!'",
                submenu: nil
            ),
        ]
    }
}

// MARK: - Main Menu Config Editor View

struct MenuConfigView: View {
    @Binding var config: [MenuItem]
    @EnvironmentObject private var configManager: ConfigManager
    
    @State private var selectedItem: MenuItem.ID? = nil
    @State private var searchText: String = ""
    @State private var expandedItems: Set<UUID> = []
    @State private var showingSaveConfirmation = false
    @State private var saveError: Error? = nil
    @State private var showMenu = false
    @State private var draggedItem: MenuItem.ID? = nil
    @State private var dragOver: MenuItem.ID? = nil
    
    var filteredItems: [MenuItem] {
        if searchText.isEmpty {
            return config
        } else {
            return filterMenuItems(config, matching: searchText.lowercased())
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar and toolbar
            MenuConfigToolbar(
                searchText: $searchText,
                onExpandAll: expandAll,
                onCollapseAll: collapseAll,
                onSave: saveConfig
            )
            
            Divider()
                .padding(.top, 8)
                .padding(.bottom, 0)
            
            HSplitView {
                // Left side: Hierarchical tree view
                MenuTreeView(
                    items: filteredItems,
                    selectedItem: $selectedItem,
                    expandedItems: $expandedItems,
                    onToggleExpanded: toggleExpanded
                )
                .listStyle(SidebarListStyle())
                .frame(minWidth: 220)
                
                // Right side: Detail editor
                if let selectedID = selectedItem, let index = findMenuItemIndex(id: selectedID, in: config) {
                    ScrollView {
                        MenuItemDetailView(
                            item: binding(for: selectedID, in: config),
                            onDelete: { deleteItem(id: selectedID) }
                        )
                        .padding()
                    }
                    .frame(minWidth: 350)
                    .background(Color(.windowBackgroundColor))
                } else {
                    EmptySelectionView(onAddItem: addNewRootItem)
                }
            }
        }
        .alert(isPresented: $showingSaveConfirmation) {
            if let error = saveError {
                return Alert(
                    title: Text("Save Error"),
                    message: Text("Failed to save config: \(error.localizedDescription)"),
                    dismissButton: .default(Text("OK"))
                )
            } else {
                return Alert(
                    title: Text("Config Saved"),
                    message: Text("Your changes have been saved to menu.yaml"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func addNewRootItem() {
        let newItem = MenuItem(
            key: "x",
            icon: "plus",
            title: "New Menu Item",
            action: nil,
            submenu: []
        )
        config.append(newItem)
        selectedItem = newItem.id
        expandedItems.insert(newItem.id)
    }
    
    private func expandAll() {
        var itemIDs = Set<UUID>()
        func collectIDs(_ items: [MenuItem]) {
            for item in items {
                itemIDs.insert(item.id)
                if let submenu = item.submenu {
                    collectIDs(submenu)
                }
            }
        }
        collectIDs(config)
        expandedItems = itemIDs
    }
    
    private func collapseAll() {
        expandedItems.removeAll()
    }
    
    private func toggleExpanded(_ id: UUID) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }
    
    private func deleteItem(id: UUID) {
        // If deleting the selected item, clear selection
        if selectedItem == id {
            selectedItem = nil
        }
        
        // Remove from expanded items set
        expandedItems.remove(id)
        
        // Find and remove the item
        removeMenuItem(id: id, from: &config)
    }
    
    private func findMenuItemIndex(id: UUID, in items: [MenuItem]) -> Int? {
        for (index, item) in items.enumerated() {
            if item.id == id {
                return index
            }
            
            if let submenu = item.submenu, let foundIndex = findMenuItemIndex(id: id, in: submenu) {
                return foundIndex
            }
        }
        return nil
    }
    
    private func removeMenuItem(id: UUID, from items: inout [MenuItem]) -> Bool {
        // Check if item exists at this level
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
            return true
        }
        
        // Check in submenus
        for i in 0..<items.count {
            if var submenu = items[i].submenu, !submenu.isEmpty {
                if removeMenuItem(id: id, from: &submenu) {
                    items[i].submenu = submenu
                    return true
                }
            }
        }
        
        return false
    }
    
    private func binding(for id: UUID, in items: [MenuItem]) -> Binding<MenuItem> {
        Binding(
            get: {
                // Find the item with matching ID
                if let index = items.firstIndex(where: { $0.id == id }) {
                    return items[index]
                }
                
                // Search in submenus
                for item in items {
                    if let submenu = item.submenu {
                        if let binding = self.binding(for: id, in: submenu).wrappedValue as MenuItem? {
                            return binding
                        }
                    }
                }
                
                // Fallback (should never happen if ID exists)
                return items[0]
            },
            set: { newValue in
                updateMenuItem(id: id, with: newValue, in: &self.config)
            }
        )
    }
    
    private func updateMenuItem(id: UUID, with newValue: MenuItem, in items: inout [MenuItem]) {
        for index in 0..<items.count {
            if items[index].id == id {
                items[index] = newValue
                return
            }
            
            if var submenu = items[index].submenu {
                updateMenuItem(id: id, with: newValue, in: &submenu)
                items[index].submenu = submenu
            }
        }
    }
    
    private func filterMenuItems(_ items: [MenuItem], matching query: String) -> [MenuItem] {
        var result: [MenuItem] = []
        
        for item in items {
            let titleMatch = item.title.lowercased().contains(query)
            let keyMatch = item.key.lowercased().contains(query)
            let actionMatch = item.action?.lowercased().contains(query) ?? false
            
            if titleMatch || keyMatch || actionMatch {
                // If this item matches, include it
                var newItem = item
                // Keep submenu intact if any
                result.append(newItem)
            } else if let submenu = item.submenu {
                // Check if any children match
                let filteredSubmenu = filterMenuItems(submenu, matching: query)
                if !filteredSubmenu.isEmpty {
                    // If children match, include this parent with only matching children
                    var newItem = item
                    newItem.submenu = filteredSubmenu
                    result.append(newItem)
                    
                    // Ensure this item is expanded in the UI
                    expandedItems.insert(item.id)
                }
            }
        }
        
        return result
    }
    
    private func saveConfig() {
        do {
            let encoder = YAMLEncoder()
            var yamlString = try encoder.encode(config)
            
            // Add a header comment to the YAML
            yamlString = "# SwiftKey Menu Configuration\n# Last modified: \(Date())\n\n" + yamlString
            
            guard let configURL = configManager.resolveConfigFileURL() else {
                self.saveError = ConfigError.fileNotFound
                self.showingSaveConfirmation = true
                return
            }
            
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
            
            // Force a config reload
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                configManager.loadConfig()
            }
            
            self.saveError = nil
            self.showingSaveConfirmation = true
        } catch {
            self.saveError = error
            self.showingSaveConfirmation = true
        }
    }
}

// MARK: - Empty Selection View

struct EmptySelectionView: View {
    var onAddItem: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "sidebar.squares.left")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Select a menu item to edit")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer().frame(height: 40)
            
            Button {
                onAddItem()
            } label: {
                Label("Add Root Menu Item", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

struct MenuConfigView_Previews: PreviewProvider {
    @State static var sampleConfig = MenuItem.sampleData()
    
    static var previews: some View {
        MenuConfigView(config: $sampleConfig)
            .frame(width: 800, height: 600)
            .environmentObject(ConfigManager.shared)
    }
}
