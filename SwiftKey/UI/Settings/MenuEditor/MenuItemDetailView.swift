import SwiftUI
import AppKit

// MARK: - Menu Item Detail View

struct MenuItemDetailView: View {
    @Binding var item: MenuItem
    var onDelete: () -> Void
    
    // State for UI controls
    @State private var isAddingSubmenuItem = false
    @State private var showingIconPicker = false
    @State private var selectedMode: ItemMode = .action
    
    // Enum for the segmented control
    enum ItemMode: String, CaseIterable {
        case action = "Action"
        case submenu = "Submenu"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header section with title and icon
            MenuItemHeaderView(
                item: $item,
                showingIconPicker: $showingIconPicker
            )
            
            // Segmented control for Action/Submenu mode
            Picker("Item Type", selection: $selectedMode) {
                ForEach(ItemMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            .onChange(of: selectedMode) { newMode in
                // Convert the item to the appropriate type based on selected mode
                if newMode == .submenu {
                    // Warning dialog if submenu has items and we're changing from action to submenu
                    let hasAction = item.action != nil && !item.action!.isEmpty
                    if hasAction {
                        // Convert to submenu type
                        item.convertToSubmenu()
                    }
                } else {
                    // Convert to action type
                    let hasNonEmptySubmenu = item.submenu != nil && !(item.submenu?.isEmpty ?? true)
                    
                    // Only convert if submenu is empty or nil
                    if !hasNonEmptySubmenu {
                        // We'll preserve the current action type if possible
                        let currentType = item.actionType
                        if currentType != .submenu && currentType != .unknown {
                            item.convertToAction(type: currentType)
                        } else {
                            // Default to launch if no valid type
                            item.convertToAction(type: .launch)
                        }
                    } else {
                        // If has submenu items, stay in submenu mode
                        selectedMode = .submenu
                    }
                }
            }
            
            Divider()
            
            // Content based on selected mode
            if selectedMode == .action {
                // Action settings view
                MenuItemActionView(item: $item)
            } else {
                // Submenu settings view
                MenuItemSubmenuView(
                    item: $item,
                    isAddingSubmenuItem: $isAddingSubmenuItem
                )
            }
            
            Divider()
                        
            // Bottom action buttons
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Item", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isAddingSubmenuItem) {
            AddSubmenuItemView(parentItem: $item, isPresented: $isAddingSubmenuItem)
                .frame(width: 450, height: 400)
        }
        .popover(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $item.icon)
                .frame(width: 300, height: 400)
        }
        .onAppear {
            // Initialize proper selected mode based on current item state
            if item.actionType == .submenu {
                selectedMode = .submenu
            } else {
                selectedMode = .action
            }
            
            // Initialize submenu if nil
            if item.submenu == nil {
                item.submenu = []
            }
        }
    }
}

// MARK: - Menu Item Header View

struct MenuItemHeaderView: View {
    @Binding var item: MenuItem
    @Binding var showingIconPicker: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                showingIconPicker.toggle()
            } label: {
                if let icon = item.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .frame(width: 60, height: 60)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            
            VStack(alignment: .leading) {
                TextField("Menu Item Title", text: $item.title)
                    .font(.title2)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.bottom, 4)
                
                HStack {
                    Text("Hotkey: ")
                        .foregroundColor(.secondary)
                    
                    TextField("key", text: $item.key)
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .background(Color(NSColor.systemGray))
                        .cornerRadius(4)
                        .onChange(of: item.key) { newValue in
                            if newValue.count > 1 {
                                item.key = String(newValue.prefix(1))
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Preview

struct MenuItemDetailView_Previews: PreviewProvider {
    @State static var sampleItem = MenuItem.sampleData()[0]
    
    static var previews: some View {
        MenuItemDetailView(
            item: $sampleItem,
            onDelete: {}
        )
        .frame(width: 500)
        .padding()
    }
}
