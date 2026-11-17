import SwiftUI
import SwiftKeyCore

struct PropertyInspectorView: View {
    @Binding var selectedItem: MenuItem?
    @EnvironmentObject private var hotkeys: HotkeyCenter
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var approvalGate: ApprovalGate
    @EnvironmentObject private var microApps: MicroAppDirectory
    let onUpdate: (MenuItem) -> Void
    let validationErrors: [ConfigEditorViewModel.ValidationError]
    
    @State private var showingSFSymbolPicker = false
    
    enum ActionType: String, CaseIterable {
        case none = "None"
        case launch = "Launch"
        case open = "Open"
        case shell = "Shell"
        case shortcut = "Shortcut"
        case dynamic = "Dynamic"
        case micro = "Micro-app"
        
        var prefix: String? {
            switch self {
            case .none: return nil
            case .launch: return "launch://"
            case .open: return "open://"
            case .shell: return "shell://"
            case .shortcut: return "shortcut://"
            case .dynamic: return "dynamic://"
            case .micro: return "micro://"
            }
        }
        
        static func from(action: String?) -> ActionType {
            guard let action = action else { return .none }
            if action.hasPrefix("launch://") { return .launch }
            if action.hasPrefix("open://") { return .open }
            if action.hasPrefix("shell://") { return .shell }
            if action.hasPrefix("shortcut://") { return .shortcut }
            if action.hasPrefix("dynamic://") { return .dynamic }
            if action.hasPrefix("micro://") { return .micro }
            return .none
        }
    }
    
    var body: some View {
        ScrollView {
            if let item = selectedItem {
                VStack(alignment: .leading, spacing: 16) {
                    basicPropertiesSection(for: item)
                    Divider()
                    actionSection(for: item)
                    Divider()
                    flagsSection(for: item)
                    Divider()
                    advancedSection(for: item)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a menu item to edit")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingSFSymbolPicker) {
            if let item = selectedItem {
                SFSymbolPicker(selectedSymbol: item.icon ?? "star") { symbol in
                    var updatedItem = item
                    updatedItem.icon = symbol
                    onUpdate(updatedItem)
                    showingSFSymbolPicker = false
                }
            }
        }
    }
    
    // MARK: - Basic Properties Section
    
    @ViewBuilder
    private func basicPropertiesSection(for item: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Properties")
                .font(.headline)
            
            // Key field
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Key:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Single character", text: Binding(
                        get: { item.key },
                        set: { newValue in
                            var updatedItem = item
                            updatedItem.key = String(newValue.prefix(1))
                            onUpdate(updatedItem)
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(hasError(for: "key") ? Color.red : Color.clear, lineWidth: 1)
                    )
                }
                if let error = validationErrors.first(where: { $0.field == "key" }) {
                    Text(error.message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 84)
                }
            }
            
            // Title field
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Title:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Menu item title", text: Binding(
                        get: { item.title },
                        set: { newValue in
                            var updatedItem = item
                            updatedItem.title = newValue
                            onUpdate(updatedItem)
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(hasError(for: "title") ? Color.red : Color.clear, lineWidth: 1)
                    )
                }
                if let error = validationErrors.first(where: { $0.field == "title" }) {
                    Text(error.message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 84)
                }
            }
            
            // Icon picker
            HStack {
                Text("Icon:")
                    .frame(width: 80, alignment: .trailing)
                Button(action: { showingSFSymbolPicker = true }) {
                    HStack {
                        if let iconName = item.icon {
                            Image(systemName: iconName)
                                .foregroundColor(.primary)
                        }
                        Text(item.icon ?? "Choose...")
                            .foregroundColor(item.icon == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if item.icon != nil {
                    Button("Clear") {
                        var updatedItem = item
                        updatedItem.icon = nil
                        onUpdate(updatedItem)
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Action Section
    
    @ViewBuilder
    private func actionSection(for item: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action")
                .font(.headline)
            
            // Action type picker
            HStack {
                Text("Type:")
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { ActionType.from(action: item.action) },
                    set: { newType in
                        var updatedItem = item
                        if newType == .none {
                            updatedItem.action = nil
                        } else if let prefix = newType.prefix {
                            updatedItem.action = prefix
                        }
                        onUpdate(updatedItem)
                    }
                )) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Action value editor
            let currentType = ActionType.from(action: item.action)
            if currentType != .none {
                actionValueEditor(for: item, type: currentType)
            }
            
            // Action validation errors
            if let error = validationErrors.first(where: { $0.field == "action" }) {
                HStack {
                    Image(systemName: error.severity == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .foregroundColor(error.severity == .warning ? .orange : .red)
                    Text(error.message)
                        .font(.caption)
                        .foregroundColor(error.severity == .warning ? .orange : .red)
                }
                .padding(.leading, 84)
            }
        }
    }
    
    @ViewBuilder
    private func actionValueEditor(for item: MenuItem, type: ActionType) -> some View {
        let actionValue = item.action?.dropFirst(type.prefix?.count ?? 0) ?? ""
        
        switch type {
        case .launch:
            HStack {
                Text("App:")
                    .frame(width: 80, alignment: .trailing)
                TextField("/Applications/App.app", text: Binding(
                    get: { String(actionValue) },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.action = "launch://\(newValue)"
                        onUpdate(updatedItem)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        var updatedItem = item
                        updatedItem.action = "launch://\(url.path)"
                        onUpdate(updatedItem)
                    }
                }
            }
            
        case .open:
            HStack {
                Text("URL:")
                    .frame(width: 80, alignment: .trailing)
                TextField("https://example.com", text: Binding(
                    get: { String(actionValue) },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.action = "open://\(newValue)"
                        onUpdate(updatedItem)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
        case .shell:
            HStack {
                Text("Command:")
                    .frame(width: 80, alignment: .trailing)
                TextField("echo 'Hello World'", text: Binding(
                    get: { String(actionValue) },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.action = "shell://\(newValue)"
                        onUpdate(updatedItem)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(.body, design: .monospaced))
            }
            
        case .shortcut:
            HStack {
                Text("Shortcut:")
                    .frame(width: 80, alignment: .trailing)
                TextField("Shortcut Name", text: Binding(
                    get: { String(actionValue) },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.action = "shortcut://\(newValue)"
                        onUpdate(updatedItem)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
        case .dynamic:
            HStack {
                Text("Script:")
                    .frame(width: 80, alignment: .trailing)
                TextField("~/scripts/menu.sh", text: Binding(
                    get: { String(actionValue) },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.action = "dynamic://\(newValue)"
                        onUpdate(updatedItem)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        var updatedItem = item
                        updatedItem.action = "dynamic://\(url.path)"
                        onUpdate(updatedItem)
                    }
                }
            }
            
        case .micro:
            microAppEditor(for: item, id: String(actionValue))

        case .none:
            EmptyView()
        }
    }

    /// Picks a loaded micro-app by id. A broken or missing id stays listed, marked, until another
    /// one is chosen; its problem shows below the picker.
    @ViewBuilder
    private func microAppEditor(for item: MenuItem, id: String) -> some View {
        let choices = microApps.choices(current: id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Micro-app:")
                    .frame(width: 80, alignment: .trailing)
                if choices.isEmpty {
                    Text("No micro-apps in \(microApps.folderURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "the micro-apps folder")")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Micro-app", selection: Binding(
                        get: { id },
                        set: { newID in
                            var updatedItem = item
                            updatedItem.action = "micro://\(newID)"
                            onUpdate(updatedItem)
                        }
                    )) {
                        if id.isEmpty {
                            Text("Choose a micro-app").tag("")
                        }
                        ForEach(choices) { choice in
                            Text(choice.title).tag(choice.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Micro-app")
                }
                Button("Reveal File") {
                    if let url = microApps.fileURL(for: id) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(microApps.fileURL(for: id) == nil)
                .help("Show the micro-app's file in Finder")
            }
            if let problem = microApps.problem(for: id) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 84)
            }
        }
    }
    
    // MARK: - Flags Section
    
    @ViewBuilder
    private func flagsSection(for item: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sticky - Keep window open after action", isOn: Binding(
                    get: { item.sticky ?? false },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.sticky = newValue ? true : nil
                        onUpdate(updatedItem)
                    }
                ))
                
                Toggle("Notify - Show notification after action", isOn: Binding(
                    get: { item.notify ?? false },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.notify = newValue ? true : nil
                        onUpdate(updatedItem)
                    }
                ))
                
                Toggle("Batch - Run all submenu items", isOn: Binding(
                    get: { item.batch ?? false },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.batch = newValue ? true : nil
                        onUpdate(updatedItem)
                    }
                ))
                .disabled(item.submenu?.isEmpty ?? true)
                
                Toggle("Hidden - Hide from UI but keep activatable", isOn: Binding(
                    get: { item.hidden ?? false },
                    set: { newValue in
                        var updatedItem = item
                        updatedItem.hidden = newValue ? true : nil
                        onUpdate(updatedItem)
                    }
                ))
            }
            .padding(.leading, 84)
        }
    }
    
    // MARK: - Advanced Section
    
    @ViewBuilder
    private func advancedSection(for item: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.headline)
            
            HStack {
                Text("Hotkey:")
                    .frame(width: 80, alignment: .trailing)
                
                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { item.hotkey ?? "" },
                        set: { newValue in
                            var updatedItem = item
                            updatedItem.hotkey = newValue.isEmpty ? nil : newValue
                            onUpdate(updatedItem)
                        }
                    ),
                    gate: hotkeys.recordingGate,
                    placeholder: "None",
                    problem: hotkeys.itemProblems[item.id],
                    conflict: { hotkey in
                        hotkey == settings.mainHotkeyValue ? "\(hotkey.display) is the SwiftKey hotkey. Press another key." : nil
                    }
                )
                .help("A global hotkey that runs this item, or opens the menu at it, from any app.")
            }
            
            HStack {
                Spacer()
                    .frame(width: 84)
                
                if item.action != nil {
                    Button("Test Action") {
                        testAction(item)
                    }
                }
                
                Button("Validate") {
                    // Validation happens automatically
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func hasError(for field: String) -> Bool {
        validationErrors.contains { $0.field == field }
    }
    
    /// Runs the item as it is now, through the same approval as a key press: the field may hold
    /// a command that was not typed here.
    private func testAction(_ item: MenuItem) {
        Task { @MainActor in
            await approvalGate.run(item, path: [])
        }
    }
}