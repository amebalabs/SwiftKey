import SwiftUI
import AppKit

// MARK: - Add Submenu Item View

struct AddSubmenuItemView: View {
    @Binding var parentItem: MenuItem
    @Binding var isPresented: Bool
    
    @State private var newItem = MenuItem(
        key: "",
        icon: "doc",
        title: "",
        action: nil,
        submenu: []
    )
    @State private var showingIconPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Submenu Item")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Icon and title
                    HStack(spacing: 16) {
                        Button {
                            showingIconPicker.toggle()
                        } label: {
                            if let icon = newItem.icon, !icon.isEmpty {
                                Image(systemName: icon)
                                    .font(.system(size: 24))
                                    .frame(width: 48, height: 48)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .frame(width: 48, height: 48)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .popover(isPresented: $showingIconPicker) {
                            IconPickerView(selectedIcon: $newItem.icon)
                                .frame(width: 300, height: 400)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("Menu Item Title", text: $newItem.title)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    // Key
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hotkey (Single Character)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Key", text: $newItem.key)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: newItem.key) { newValue in
                                if newValue.count > 1 {
                                    newItem.key = String(newValue.prefix(1))
                                }
                            }
                    }
                    
                    // Action
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Action (e.g., launch:///Applications/TextEdit.app)", text: Binding(
                            get: { newItem.action ?? "" },
                            set: { newItem.action = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Examples: launch:///Applications/Safari.app, open://https://example.com, shell://echo 'Hello'")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Add") {
                    // Ensure submenu exists
                    if parentItem.submenu == nil {
                        parentItem.submenu = []
                    }
                    
                    // Add the new item
                    parentItem.submenu?.append(newItem)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newItem.title.isEmpty || newItem.key.isEmpty)
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct AddSubmenuItemView_Previews: PreviewProvider {
    @State static var parentItem = MenuItem.sampleData()[0]
    @State static var isPresented = true
    
    static var previews: some View {
        AddSubmenuItemView(
            parentItem: $parentItem,
            isPresented: $isPresented
        )
        .frame(width: 450, height: 400)
    }
}