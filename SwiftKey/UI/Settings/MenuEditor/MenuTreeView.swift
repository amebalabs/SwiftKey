import SwiftUI

struct MenuTreeView: View {
    // Now using @Binding to allow direct modification of the source items
    @Binding var items: [MenuItem]
    @Binding var selectedItem: MenuItem.ID?
    @Binding var expandedItems: Set<UUID>
    let onAddRootItem: () -> Void
    
    // New properties for handling submenu creation
    @State private var isAddingSubmenuItem = false
    @State private var currentEditingItemID: UUID?
    
    var body: some View {
        List(selection: $selectedItem) {
            if !items.isEmpty {
                OutlineView(
                    items: $items,
                    selectedItem: $selectedItem,
                    expandedItems: $expandedItems,
                    onAddSubmenuItem: { itemID in
                        currentEditingItemID = itemID
                        isAddingSubmenuItem = true
                    }
                )
            } else {
                Text("No menu items")
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Button(action: onAddRootItem) {
                Label("Add Root Item", systemImage: "plus.circle")
            }
            .padding(.top, 8)
        }
        .listStyle(SidebarListStyle())
        .environment(\.defaultMinListRowHeight, 30)
        .onChange(of: items) { newItems in
            // Check if selected item still exists in the list
            if let selectedID = selectedItem, !newItems.isEmpty {
                let itemExists = itemExistsInHierarchy(id: selectedID, items: newItems)
                if !itemExists {
                    // If selected item doesn't exist anymore, select the first item
                    selectedItem = newItems[0].id
                }
            } else if !newItems.isEmpty {
                // If nothing is selected and we have items, select the first one
                selectedItem = newItems[0].id
            }
        }
        .sheet(isPresented: $isAddingSubmenuItem) {
            if let editingItemID = currentEditingItemID,
                let binding = findBindingForItem(id: editingItemID, in: $items) {
                AddSubmenuItemView(
                    parentItem: binding,
                    isPresented: $isAddingSubmenuItem
                )
                .frame(width: 450, height: 400)
            }
        }
    }
    
    // Function to find the binding for an item with specific ID
    private func findBindingForItem(id: UUID, in items: Binding<[MenuItem]>) -> Binding<MenuItem>? {
        for index in 0..<items.wrappedValue.count {
            if items.wrappedValue[index].id == id {
                return items[index]
            }
            
            if let submenu = items.wrappedValue[index].submenu, !submenu.isEmpty {
                // Create a binding for the submenu
                let submenuBinding = Binding<[MenuItem]>(
                    get: { items.wrappedValue[index].submenu ?? [] },
                    set: { newValue in
                        var updatedItems = items.wrappedValue
                        updatedItems[index].submenu = newValue
                        items.wrappedValue = updatedItems
                    }
                )
                
                // Recursively search in the submenu
                if let binding = findBindingForItem(id: id, in: submenuBinding) {
                    return binding
                }
            }
        }
        
        return nil
    }
    
    // Recursively check if an item exists in the hierarchy
    private func itemExistsInHierarchy(id: UUID, items: [MenuItem]) -> Bool {
        for item in items {
            if item.id == id {
                return true
            }
            if let submenu = item.submenu, !submenu.isEmpty {
                if itemExistsInHierarchy(id: id, items: submenu) {
                    return true
                }
            }
        }
        return false
    }
    
    private struct OutlineView: View {
        @Binding var items: [MenuItem]
        @Binding var selectedItem: MenuItem.ID?
        @Binding var expandedItems: Set<UUID>
        let onAddSubmenuItem: (UUID) -> Void
        
        var body: some View {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                
                if hasSubmenu(item) {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedItems.contains(item.id) },
                            set: { newValue in
                                if newValue {
                                    expandedItems.insert(item.id)
                                } else {
                                    expandedItems.remove(item.id)
                                }
                            }
                        ),
                        content: {
                            if let submenu = item.submenu, !submenu.isEmpty {
                                // Create a binding for submenu
                                let submenuBinding = Binding<[MenuItem]>(
                                    get: { items[index].submenu ?? [] },
                                    set: { newValue in
                                        var updatedItems = items
                                        updatedItems[index].submenu = newValue
                                        items = updatedItems
                                    }
                                )
                                
                                OutlineView(
                                    items: submenuBinding,
                                    selectedItem: $selectedItem,
                                    expandedItems: $expandedItems,
                                    onAddSubmenuItem: onAddSubmenuItem
                                )
                            }
                        },
                        label: {
                            MenuItemRow(item: item)
                                .contentShape(Rectangle())
                                .tag(item.id)
                                .onTapGesture {
                                    selectedItem = item.id
                                }
                        }
                    )
                    .contextMenu {
                        Button(action: { toggleExpansion(for: item) }) {
                            Label(
                                expandedItems.contains(item.id) ? "Collapse" : "Expand", 
                                systemImage: expandedItems.contains(item.id) ? "chevron.up" : "chevron.down"
                            )
                        }
                        
                        Divider()
                        
                        Button(action: { onAddSubmenuItem(item.id) }) {
                            Label("Add Submenu Item", systemImage: "plus.circle")
                        }
                    }
                } else {
                    MenuItemRow(item: item)
                        .contentShape(Rectangle())
                        .tag(item.id)
                        .onTapGesture {
                            selectedItem = item.id
                        }
                        .contextMenu {
                            Button(action: { onAddSubmenuItem(item.id) }) {
                                Label("Add Submenu Item", systemImage: "plus.circle")
                            }
                        }
                }
            }
        }
        
        private func hasSubmenu(_ item: MenuItem) -> Bool {
            return item.submenu != nil && !(item.submenu?.isEmpty ?? true)
        }
        
        private func toggleExpansion(for item: MenuItem) {
            if hasSubmenu(item) {
                if expandedItems.contains(item.id) {
                    expandedItems.remove(item.id)
                } else {
                    expandedItems.insert(item.id)
                }
            }
        }
    }
    
    private struct MenuItemRow: View {
        let item: MenuItem
        
        var body: some View {
            HStack {
                Label {
                    Text(item.title)
                        .lineLimit(1)
                } icon: {
                    let hasSubmenu = item.submenu != nil && !(item.submenu?.isEmpty ?? true)
                    
                    if let icon = item.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .foregroundColor(.accentColor)
                    } else if hasSubmenu {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "doc")
                            .foregroundColor(.accentColor)
                    }
                }
                Spacer()
                Text(item.key)
                    .font(.system(.caption, design: .monospaced))
                    .padding(2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
    }
}
