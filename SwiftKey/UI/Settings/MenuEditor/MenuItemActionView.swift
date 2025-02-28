import SwiftUI
import AppKit

// MARK: - Menu Item Action View

struct MenuItemActionView: View {
    @Binding var item: MenuItem
    @Binding var actionType: String
    let actionTypes: [String]
    
    var body: some View {
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
                ActionOptionsView(item: $item)
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
}

// MARK: - Action Options View

struct ActionOptionsView: View {
    @Binding var item: MenuItem
    
    var body: some View {
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

// MARK: - Preview

struct MenuItemActionView_Previews: PreviewProvider {
    @State static var sampleItem = MenuItem.sampleData()[0]
    @State static var actionType = "launch"
    static let actionTypes = ["launch", "open", "shell", "shortcut", "dynamic"]
    
    static var previews: some View {
        MenuItemActionView(
            item: $sampleItem,
            actionType: $actionType,
            actionTypes: actionTypes
        )
        .padding()
        .frame(width: 500)
    }
}