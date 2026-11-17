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

        /// The name in the type pop-up.
        var menuTitle: String {
            switch self {
            case .none: return "None"
            case .launch: return "Launch App"
            case .open: return "Open URL"
            case .shell: return "Shell Command"
            case .shortcut: return "Run Shortcut"
            case .dynamic: return "Dynamic Menu"
            case .micro: return "Micro-app"
            }
        }

        var symbol: String {
            switch self {
            case .none: return "circle.slash"
            case .launch: return "app"
            case .open: return "link"
            case .shell: return "terminal"
            case .shortcut: return "square.2.layers.3d"
            case .dynamic: return "list.bullet.indent"
            case .micro: return "puzzlepiece.extension"
            }
        }
    }

    var body: some View {
        Group {
            if let item = selectedItem {
                Form {
                    itemSection(for: item)
                    actionSection(for: item)
                    optionsSection(for: item)
                    hotkeySection(for: item)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "No Item Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a menu item to edit it.")
                )
            }
        }
        // Fill the pane whether a form or the empty state shows, so the split view keeps its height.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Item Section

    @ViewBuilder
    private func itemSection(for item: MenuItem) -> some View {
        Section {
            // A single character keeps its case; named keys are space, return and f1…f20.
            TextField("Key", text: Binding(
                get: { item.key },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.key = newValue
                    onUpdate(updatedItem)
                }
            ), prompt: Text("a, B, space, f5"))
            .font(.system(.body, design: .monospaced))
            fieldError("key")

            TextField("Title", text: Binding(
                get: { item.title },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.title = newValue
                    onUpdate(updatedItem)
                }
            ), prompt: Text("Menu item title"))
            fieldError("title")

            LabeledContent("Icon") {
                HStack(spacing: 8) {
                    Button(action: { showingSFSymbolPicker = true }) {
                        if let iconName = item.icon {
                            Label(iconName, systemImage: iconName)
                        } else {
                            Text("Choose…")
                        }
                    }
                    if item.icon != nil {
                        Button("Clear") {
                            var updatedItem = item
                            updatedItem.icon = nil
                            onUpdate(updatedItem)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Item")
        }
    }

    // MARK: - Action Section

    @ViewBuilder
    private func actionSection(for item: MenuItem) -> some View {
        let currentType = ActionType.from(action: item.action)
        Section {
            Picker("Type", selection: Binding(
                get: { currentType },
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
                    Label(type.menuTitle, systemImage: type.symbol).tag(type)
                }
            }

            if currentType != .none {
                actionValueEditor(for: item, type: currentType)
            }

            if let error = validationErrors.first(where: { $0.field == "action" }) {
                issueRow(error)
            }
        } header: {
            Text("Action")
        } footer: {
            if item.submenu != nil, currentType == .none {
                Text("A group opens its submenu.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionValueEditor(for item: MenuItem, type: ActionType) -> some View {
        let actionValue = item.action?.dropFirst(type.prefix?.count ?? 0) ?? ""
        let value = Binding(
            get: { String(actionValue) },
            set: { (newValue: String) in
                var updatedItem = item
                updatedItem.action = (type.prefix ?? "") + newValue
                onUpdate(updatedItem)
            }
        )

        switch type {
        case .launch:
            LabeledContent("App") {
                HStack {
                    TextField("App", text: value, prompt: Text("/Applications/App.app or com.apple.Safari"))
                        .labelsHidden()
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")

                        if panel.runModal() == .OK, let url = panel.url {
                            value.wrappedValue = url.path
                        }
                    }
                }
            }

        case .open:
            TextField("URL", text: value, prompt: Text("https://example.com"))

        case .shell:
            TextField("Command", text: value, prompt: Text("echo 'Hello World'"), axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)

        case .shortcut:
            TextField("Shortcut", text: value, prompt: Text("Shortcut name"))

        case .dynamic:
            LabeledContent("Script") {
                HStack {
                    TextField("Script", text: value, prompt: Text("~/scripts/menu.sh"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true

                        if panel.runModal() == .OK, let url = panel.url {
                            value.wrappedValue = url.path
                        }
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
        if choices.isEmpty {
            LabeledContent("Micro-app") {
                Text("No micro-apps in \(microApps.folderURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "the micro-apps folder")")
                    .foregroundStyle(.secondary)
            }
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
        }
        LabeledContent("File") {
            Button("Reveal in Finder") {
                if let url = microApps.fileURL(for: id) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(microApps.fileURL(for: id) == nil)
            .help("Show the micro-app's file in Finder")
        }
        if let problem = microApps.problem(for: id) {
            Label {
                Text(problem)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private func optionsSection(for item: MenuItem) -> some View {
        Section {
            optionToggle("Sticky", "Keep the menu open after the action runs.", isOn: Binding(
                get: { item.sticky ?? false },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.sticky = newValue ? true : nil
                    onUpdate(updatedItem)
                }
            ))

            optionToggle("Notify", "Show a notification when the action finishes.", isOn: Binding(
                get: { item.notify ?? false },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.notify = newValue ? true : nil
                    onUpdate(updatedItem)
                }
            ))

            optionToggle("Batch", item.submenu?.isEmpty ?? true
                ? "Only for groups: runs every item in the submenu."
                : "Run every item in the submenu at once.", isOn: Binding(
                get: { item.batch ?? false },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.batch = newValue ? true : nil
                    onUpdate(updatedItem)
                }
            ))
            .disabled(item.submenu?.isEmpty ?? true)
            fieldError("batch")

            optionToggle("Hidden", "Leave out of the menu and launcha; the key still works.", isOn: Binding(
                get: { item.hidden ?? false },
                set: { newValue in
                    var updatedItem = item
                    updatedItem.hidden = newValue ? true : nil
                    onUpdate(updatedItem)
                }
            ))
        } header: {
            Text("Options")
        }
    }

    private func optionToggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }

    // MARK: - Hotkey Section

    @ViewBuilder
    private func hotkeySection(for item: MenuItem) -> some View {
        Section {
            LabeledContent("Global hotkey") {
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
            }
            fieldError("hotkey")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("Runs this item, or opens the menu at it, from any app.")
                    .foregroundStyle(.secondary)
                Spacer()
                if item.action != nil {
                    Button("Test Action") {
                        testAction(item)
                    }
                    .help("Run this item now, with the same approval as a key press")
                }
            }
        }
    }

    // MARK: - Helpers

    /// The validation problem of one field, shown under it.
    @ViewBuilder
    private func fieldError(_ field: String) -> some View {
        if let error = validationErrors.first(where: { $0.field == field }) {
            issueRow(error)
        }
    }

    private func issueRow(_ error: ConfigEditorViewModel.ValidationError) -> some View {
        Label {
            Text(error.message)
        } icon: {
            Image(systemName: error.severity == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .foregroundStyle(error.severity == .warning ? .orange : .red)
        }
        .font(.callout)
        .foregroundStyle(error.severity == .warning ? Color.secondary : Color.red)
    }

    /// Runs the item as it is now, through the same approval as a key press: the field may hold
    /// a command that was not typed here.
    private func testAction(_ item: MenuItem) {
        Task { @MainActor in
            await approvalGate.run(item, path: [])
        }
    }
}
