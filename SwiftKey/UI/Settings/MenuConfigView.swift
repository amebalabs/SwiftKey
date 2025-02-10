import SwiftUI

// Sample data for testing and previews.
extension MenuItem {
    static func sampleData() -> [MenuItem] {
        return [
            MenuItem(
                key: "a",
                systemImage: "star.fill",
                title: "Launch Calculator",
                action: "launch://Calculator",
                submenu: [
                    MenuItem(
                        key: "b",
                        systemImage: "safari",
                        title: "Open Website",
                        action: "open://https://www.example.com",
                        submenu: nil
                    ),
                ]
            ),
            MenuItem(
                key: "c",
                systemImage: "printer",
                title: "Print Message",
                action: "print://Hello, World!",
                submenu: nil
            ),
        ]
    }
}

// MARK: - Full Configuration Editor View

/// This view renders the entire menu configuration as an indented, inline editor.
/// Each row provides text fields for key, title, action; a dropdown for system images;
/// and buttons to add or remove items. Submenu items are rendered recursively.
struct MenuConfigView: View {
    @Binding var config: [MenuItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(Array(config.enumerated()), id: \.element.id) { index, _ in
                    MenuItemEditorRow(
                        item: $config[index],
                        level: 0,
                        onDelete: { config.remove(at: index) }
                    )
                }
                Button(action: {
                    config.append(MenuItem(
                        key: "",
                        systemImage: "questionmark",
                        title: "New Menu Item",
                        action: nil,
                        submenu: []
                    ))
                }) {
                    Label("Add Menu Item", systemImage: "plus")
                }
                .padding(.top, 10)
            }
            .padding()
        }
    }
}

/// Recursive row view for editing a single MenuItem.
/// Displays inline editable fields and renders submenu items with indentation.
struct MenuItemEditorRow: View {
    @Binding var item: MenuItem
    var level: Int
    var onDelete: (() -> Void)? = nil

    @State private var isExpanded: Bool = true

    // Example options for SF Symbols.
    let systemImageOptions = ["star.fill", "questionmark", "safari", "printer", "folder"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Indentation spacer based on nesting level.
                Spacer().frame(width: CGFloat(level) * 20)

                // Disclosure button if the item has submenu items.
                if let submenu = item.submenu, !submenu.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .frame(width: 20)
                } else {
                    Spacer().frame(width: 20)
                }

                // Editable fields for key, title, system image, and action.
                TextField("Key", text: $item.key)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 50)

                TextField("Title", text: $item.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)

                Picker(selection: $item.systemImage, label: Text("")) {
                    ForEach(systemImageOptions, id: \.self) { image in
                        HStack {
                            Image(systemName: image)
                            Text(image)
                        }
                        .tag(image)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)

                TextField("Action", text: Binding(
                    get: { item.action ?? "" },
                    set: { item.action = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)

                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(.vertical, 4)

            // Render submenu items recursively if present.
            if let _ = item.submenu, isExpanded {
                ForEach(Array((item.submenu ?? []).enumerated()), id: \.element.id) { index, _ in
                    MenuItemEditorRow(
                        item: Binding(
                            get: { item.submenu![index] },
                            set: { item.submenu![index] = $0 }
                        ),
                        level: level + 1,
                        onDelete: {
                            item.submenu?.remove(at: index)
                        }
                    )
                }
                Button(action: {
                    if item.submenu == nil { item.submenu = [] }
                    item.submenu?.append(MenuItem(
                        key: "",
                        systemImage: "questionmark",
                        title: "New Submenu Item",
                        action: nil,
                        submenu: []
                    ))
                }) {
                    Label("Add Submenu Item", systemImage: "plus")
                        .padding(.leading, CGFloat(level + 1) * 20)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.leading, CGFloat(level) * 10)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview

struct FullConfigEditorView_Previews: PreviewProvider {
    @State static var sampleConfig = MenuItem.sampleData()

    static var previews: some View {
        MenuConfigView(config: $sampleConfig)
            .frame(width: 800, height: 400)
    }
}
