import SwiftUI
import AppKit

// MARK: - Menu Item Submenu View

struct MenuItemSubmenuView: View {
    @Binding var item: MenuItem
    @Binding var isAddingSubmenuItem: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description explaining submenu functionality
            Text("This item functions as a submenu, containing other menu items.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
                
            // Submenu options
            GroupBox {
                SubmenuOptionsView(item: $item)
            }
            .padding(.bottom, 8)
            
            // Submenu items list section
            HStack {
                Text("Submenu Items")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    isAddingSubmenuItem = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            
            if let submenu = item.submenu, !submenu.isEmpty {
                SubmenuItemsList(item: $item)
            } else {
                EmptySubmenuView(onAddItem: { isAddingSubmenuItem = true })
            }
        }
    }
}

// MARK: - Submenu Options View

struct SubmenuOptionsView: View {
    @Binding var item: MenuItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Batch (run all submenu items)", isOn: batchBinding)
                .toggleStyle(SwitchToggleStyle())
                .help("When enabled, all submenu items will be executed in sequence when this item is activated")
            
            // Can add other submenu-specific options here
        }
        .padding(.vertical, 6)
    }
    
    // Binding for the batch property
    private var batchBinding: Binding<Bool> {
        Binding(
            get: { item.batch ?? false },
            set: { item.batch = $0 }
        )
    }
}

// MARK: - Submenu Items List

struct SubmenuItemsList: View {
    @Binding var item: MenuItem
    
    var body: some View {
        List {
            ForEach(Array(item.submenu!.enumerated()), id: \.element.id) { index, subItem in
                HStack {
                    if let icon = subItem.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                    }
                    
                    Text(subItem.title)
                    
                    Spacer()
                    
                    Text(subItem.key)
                        .font(.system(.caption, design: .monospaced))
                        .padding(2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                    
                    Button {
                        item.submenu?.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minHeight: 100, maxHeight: 200)
        .background(Color(NSColor.systemGray))
        .cornerRadius(8)
    }
}

// MARK: - Empty Submenu View

struct EmptySubmenuView: View {
    var onAddItem: () -> Void
    
    var body: some View {
        VStack {
            Text("No submenu items")
                .foregroundColor(.secondary)
            Button {
                onAddItem()
            } label: {
                Text("Add First Item")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color(NSColor.systemGray))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct MenuItemSubmenuView_Previews: PreviewProvider {
    @State static var sampleItem = MenuItem.sampleData()[0]
    @State static var isAdding = false
    
    static var previews: some View {
        MenuItemSubmenuView(
            item: $sampleItem,
            isAddingSubmenuItem: $isAdding
        )
        .padding()
        .frame(width: 500)
    }
}