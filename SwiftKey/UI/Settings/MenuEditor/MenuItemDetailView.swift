import SwiftUI
import AppKit

// MARK: - Menu Item Detail View

struct MenuItemDetailView: View {
    @Binding var item: MenuItem
    var onDelete: () -> Void
    
    @State private var selectedTab = 0
    @State private var isAddingSubmenuItem = false
    @State private var showingIconPicker = false
    @State private var actionType: String = "launch"
    
    private let actionTypes = ["launch", "open", "shell", "shortcut", "dynamic"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title and icon header
            MenuItemHeaderView(
                item: $item,
                showingIconPicker: $showingIconPicker
            )
            
            Divider()
            
            // Action settings
            MenuItemActionView(
                item: $item,
                actionType: $actionType,
                actionTypes: actionTypes
            )
            
            Divider()
            
            // Submenu section
            MenuItemSubmenuView(
                item: $item,
                isAddingSubmenuItem: $isAddingSubmenuItem
            )
            
            Spacer()
            
            // Bottom action buttons
            HStack {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Item", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                
                Spacer()
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
            // Set the initial action type based on the current action
            if let action = item.action, !action.isEmpty {
                for prefix in actionTypes {
                    if action.hasPrefix("\(prefix)://") {
                        actionType = prefix
                        break
                    }
                }
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