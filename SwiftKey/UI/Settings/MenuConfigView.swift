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
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search menu items", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(7)
                .background(Color(NSColor.systemGray))
                .cornerRadius(8)
                
                Spacer()
                
                Button(action: expandAll) {
                    Label("Expand All", systemImage: "chevron.down.square")
                }
                .buttonStyle(.borderless)
                
                Button(action: collapseAll) {
                    Label("Collapse All", systemImage: "chevron.right.square")
                }
                .buttonStyle(.borderless)
                
                Button(action: { saveConfig() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            
            Divider()
                .padding(.top, 8)
                .padding(.bottom, 0)
            
            HSplitView {
                // Left side: Hierarchical tree view
                List(selection: $selectedItem) {
                    menuTreeSection(items: filteredItems, path: [])
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 220)
                
                // Right side: Detail editor
                if let selectedID = selectedItem, let index = findMenuItemIndex(id: selectedID, in: config) {
                    ScrollView {
                        MenuItemDetailEditor(
                            item: binding(for: selectedID, in: config),
                            onDelete: { deleteItem(id: selectedID) }
                        )
                        .padding()
                    }
                    .frame(minWidth: 350)
                    .background(Color(.windowBackgroundColor))
                } else {
                    VStack {
                        Image(systemName: "sidebar.squares.left")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Select a menu item to edit")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer().frame(height: 40)
                        
                        Button {
                            addNewRootItem()
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
    
    // MARK: - Menu Tree Section
    
    @ViewBuilder
    func menuTreeSection(items: [MenuItem], path: [Int]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let currentPath = path + [index]
            let hasSubmenu = item.submenu != nil && !(item.submenu?.isEmpty ?? true)
            let isExpanded = expandedItems.contains(item.id)
            
            HStack {
                Label {
                    Text(item.title)
                        .lineLimit(1)
                } icon: {
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
            .contentShape(Rectangle())
            .id(item.id)
            .tag(item.id)
            .onTapGesture {
                selectedItem = item.id
                if hasSubmenu {
                    toggleExpanded(item.id)
                }
            }
            
            if hasSubmenu && isExpanded {
                menuTreeSection(items: item.submenu!, path: currentPath)
                    .padding(.leading, 15)
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

// MARK: - MenuItem Detail Editor

struct MenuItemDetailEditor: View {
    @Binding var item: MenuItem
    var onDelete: () -> Void
    
    @State private var selectedTab = 0
    @State private var isAddingSubmenuItem = false
    @State private var iconSearchText = ""
    @State private var showingIconPicker = false
    @State private var iconResults: [String] = []
    @State private var actionType: String = "launch"
    
    private let actionTypes = ["launch", "open", "shell", "shortcut", "dynamic"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title and icon header
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
                .popover(isPresented: $showingIconPicker) {
                    IconPickerView(selectedIcon: $item.icon)
                        .frame(width: 300, height: 400)
                }
                
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
            
            Divider()
            
            // Action settings
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Action Type")
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("", selection: $actionType) {
                        ForEach(actionTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 350)
                    .onChange(of: actionType) { newValue in
                        // Update the action prefix if an action exists
                        if let existingAction = item.action, !existingAction.isEmpty {
                            // Find the part after the prefix
                            if let range = existingAction.range(of: "://") {
                                let paramPart = existingAction[range.upperBound...]
                                item.action = "\(newValue)://\(paramPart)"
                            } else {
                                // No valid prefix found, create a new action
                                item.action = "\(newValue)://"
                            }
                        } else {
                            // Create a new empty action with the selected prefix
                            item.action = "\(newValue)://"
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(actionLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(actionType)://")
                            .foregroundColor(.secondary)
                        
                        TextField("", text: actionPathBinding)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color(NSColor.systemGray))
                            .cornerRadius(6)
                    }
                    
                    Text(actionHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                
                // Action options
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Sticky (don't close menu after execution)", isOn: stickyBinding)
                            .toggleStyle(SwitchToggleStyle())
                        
                        Toggle("Show notification after execution", isOn: notifyBinding)
                            .toggleStyle(SwitchToggleStyle())
                        
                        if item.submenu != nil && !(item.submenu?.isEmpty ?? true) {
                            Toggle("Batch (run all submenu items)", isOn: batchBinding)
                                .toggleStyle(SwitchToggleStyle())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            
            Divider()
            
            // Submenu section
            VStack(alignment: .leading, spacing: 8) {
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
                    List {
                        ForEach(Array(submenu.enumerated()), id: \.element.id) { index, subItem in
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
                } else {
                    VStack {
                        Text("No submenu items")
                            .foregroundColor(.secondary)
                        Button {
                            isAddingSubmenuItem = true
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
    
    // Computed properties for action fields
    private var actionLabel: String {
        switch actionType {
        case "launch": return "Application Path:"
        case "open": return "URL to Open:"
        case "shell": return "Shell Command:"
        case "shortcut": return "Shortcut Name:"
        case "dynamic": return "Dynamic Command:"
        default: return "Action Parameter:"
        }
    }
    
    private var actionHelpText: String {
        switch actionType {
        case "launch":
            return "Path to the application to launch. For system apps, use /System/Applications/AppName.app, for user apps use /Applications/AppName.app"
        case "open":
            return "URL to open in the default browser, e.g., https://example.com"
        case "shell":
            return "Shell command to execute. Use safe commands that don't need elevated privileges."
        case "shortcut":
            return "Name of the Shortcuts automation to run"
        case "dynamic":
            return "Shell command that returns YAML for dynamic menu generation"
        default:
            return ""
        }
    }
    
    // Binding for the action path (everything after the prefix)
    private var actionPathBinding: Binding<String> {
        Binding(
            get: {
                guard let action = item.action, !action.isEmpty else { return "" }
                if let range = action.range(of: "://") {
                    return String(action[range.upperBound...])
                }
                return ""
            },
            set: { newValue in
                item.action = "\(actionType)://\(newValue)"
            }
        )
    }
    
    // Bindings for optional boolean properties
    private var stickyBinding: Binding<Bool> {
        Binding(
            get: { item.sticky ?? false },
            set: { item.sticky = $0 }
        )
    }
    
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { item.notify ?? false },
            set: { item.notify = $0 }
        )
    }
    
    private var batchBinding: Binding<Bool> {
        Binding(
            get: { item.batch ?? false },
            set: { item.batch = $0 }
        )
    }
}

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

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Binding var selectedIcon: String?
    @State private var searchText = ""
    @State private var recentIcons = ["star.fill", "folder", "doc", "gear", "bell", "iphone", "mail", "safari", "message"]
    
    // This is a subset of SF Symbols for the demo - in a real app, you'd use a more complete list
    let commonIcons = [
        "folder", "doc", "star", "star.fill", "heart", "heart.fill", "person", "person.fill",
        "gear", "gearshape", "gearshape.fill", "bell", "bell.fill", "link", "globe",
        "safari", "message", "mail", "mail.fill", "phone", "phone.fill", "video", "video.fill",
        "house", "house.fill", "square", "circle", "triangle", "rectangle", "diamond",
        "terminal", "terminal.fill", "printer", "printer.fill", "chevron.right", "chevron.down",
        "arrow.right", "arrow.up", "arrow.down", "arrow.left", "plus", "minus", "xmark",
        "clock", "clock.fill", "calendar", "calendar.badge.plus", "bookmark", "bookmark.fill",
        "tag", "tag.fill", "bolt", "bolt.fill", "magnifyingglass", "trash", "trash.fill",
        "pencil", "square.and.pencil", "checkmark", "checkmark.circle", "checkmark.circle.fill",
        "xmark.circle", "xmark.circle.fill", "exclamationmark.triangle", "questionmark.circle",
        "info.circle", "lock", "lock.fill", "lock.open", "lock.open.fill", "key", "key.fill",
        "lightbulb", "lightbulb.fill", "flag", "flag.fill", "location", "location.fill",
        "gift", "gift.fill", "cart", "cart.fill", "creditcard", "creditcard.fill"
    ]
    
    var filteredIcons: [String] {
        if searchText.isEmpty {
            return commonIcons
        } else {
            return commonIcons.filter { $0.contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search icons", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.systemGray))
            
            if searchText.isEmpty {
                // Recent icons section
                VStack(alignment: .leading) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(recentIcons, id: \.self) { icon in
                            IconButton(icon: icon, isSelected: selectedIcon == icon) {
                                selectedIcon = icon
                                updateRecentIcons(icon)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // All icons grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(filteredIcons, id: \.self) { icon in
                        IconButton(icon: icon, isSelected: selectedIcon == icon) {
                            selectedIcon = icon
                            updateRecentIcons(icon)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func updateRecentIcons(_ icon: String) {
        // Remove if already exists
        recentIcons.removeAll { $0 == icon }
        
        // Add to beginning
        recentIcons.insert(icon, at: 0)
        
        // Limit to 8 recent items
        if recentIcons.count > 8 {
            recentIcons = Array(recentIcons.prefix(8))
        }
    }
}

struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                
                if isSelected {
                    Text(icon)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - Preview

struct FullConfigEditorView_Previews: PreviewProvider {
    @State static var sampleConfig = MenuItem.sampleData()
    
    static var previews: some View {
        MenuConfigView(config: $sampleConfig)
            .frame(width: 800, height: 600)
            .environmentObject(ConfigManager.shared)
    }
}
