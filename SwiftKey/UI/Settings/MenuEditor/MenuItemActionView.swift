import SwiftUI
import AppKit

// MARK: - Menu Item Action View

struct MenuItemActionView: View {
    @Binding var item: MenuItem
    @State private var selectedType: ActionType
    
    // Initialize with correct action type
    init(item: Binding<MenuItem>) {
        self._item = item
        // Set the initial type based on the item's action
        let currentType = item.wrappedValue.actionType
        // Only use actual action types, not submenu or unknown
        if currentType == .submenu || currentType == .unknown {
            self._selectedType = State(initialValue: .launch)
        } else {
            self._selectedType = State(initialValue: currentType)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Action type selection
            HStack {
                Text("Action Type")
                    .font(.headline)
                
                Spacer()
                
                if item.actionType == .submenu {
                    // For submenu items, show a different UI
                    Text("Submenu")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    // For regular items, show action type picker
                    Picker("", selection: $selectedType) {
                        ForEach(ActionType.selectableTypes, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 350)
                    .onChange(of: selectedType) { newType in
                        // Update the action with the new type
                        let currentParam = item.actionParameter
                        item.updateAction(type: newType, parameter: currentParam)
                    }
                }
            }
            
            // Only show action parameter UI if not a submenu
            if item.actionType != .submenu {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedType.label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(selectedType.prefix)")
                            .foregroundColor(.secondary)
                        
                        TextField("", text: actionParameterBinding)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color(NSColor.systemGray))
                            .cornerRadius(6)
                    }
                    
                    Text(selectedType.helpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            
            // Action options - show for all items
            GroupBox {
                ActionOptionsView(item: $item)
            }
        }
    }
    
    // Binding for the action parameter
    private var actionParameterBinding: Binding<String> {
        Binding(
            get: { item.actionParameter },
            set: { newValue in
                item.updateAction(type: selectedType, parameter: newValue)
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
            item: $sampleItem
        )
        .padding()
        .frame(width: 500)
    }
}
