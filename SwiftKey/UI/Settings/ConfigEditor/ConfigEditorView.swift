import SwiftUI

struct ConfigEditorView: View {
    @StateObject private var viewModel = ConfigEditorViewModel()
    @State private var showingImportDialog = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            if viewModel.isLoading {
                ProgressView("Loading configuration...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else {
                HSplitView {
                    // Menu tree (40%)
                    menuTreePanel
                        .frame(minWidth: 250, idealWidth: 350, maxWidth: 400)
                    
                    // Property inspector (60%)
                    propertyInspectorPanel
                        .frame(minWidth: 350, idealWidth: 500)
                }
            }
            
            Divider()
            
            // Footer with action buttons
            footerView
        }
        .frame(width: 900, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Config Editor")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            if viewModel.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Modified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Menu Tree Panel
    
    private var menuTreePanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 4) {
                Button(action: { viewModel.addMenuItem() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Add menu item")
                
                Button(action: deleteSelectedItem) {
                    Image(systemName: "minus")
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(viewModel.selectedItem == nil)
                .help("Delete selected item")
                
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
                
                Button(action: moveItemUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!canMoveUp)
                .help("Move up")
                
                Button(action: moveItemDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!canMoveDown)
                .help("Move down")
                
                Spacer()
                
                if !viewModel.validationErrors.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("\(viewModel.validationErrors.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .help("\(viewModel.validationErrors.count) validation issues")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Tree view
            MenuTreeView(
                menuItems: $viewModel.menuItems,
                selectedItem: $viewModel.selectedItem,
                selectedItemPath: $viewModel.selectedItemPath,
                onDelete: viewModel.deleteMenuItem,
                onMove: viewModel.moveMenuItem
            )
        }
    }
    
    // MARK: - Property Inspector Panel
    
    private var propertyInspectorPanel: some View {
        PropertyInspectorView(
            selectedItem: $viewModel.selectedItem,
            onUpdate: viewModel.updateMenuItem,
            validationErrors: viewModel.selectedItem.flatMap { viewModel.validationErrors[$0.id] } ?? []
        )
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Button("Open in Editor") {
                openInExternalEditor()
            }
            .help("Open the YAML file in your default text editor")
            
            Button("Import...") {
                showingImportDialog = true
            }
            .help("Import configuration from file")
            
            Spacer()
            
            // Undo/Redo buttons
            if viewModel.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Button(action: viewModel.undo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(!viewModel.canUndo)
                    .help("Undo")
                    
                    Button(action: viewModel.redo) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(!viewModel.canRedo)
                    .help("Redo")
                }
                
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
            }
            
            Button("Cancel") {
                if viewModel.hasUnsavedChanges {
                    showDiscardAlert()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Button("Save Changes") {
                saveConfiguration()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.hasUnsavedChanges || hasValidationErrors)
        }
        .padding()
    }
    
    // MARK: - Error View
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Failed to load configuration")
                .font(.headline)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            HStack {
                Button("Retry") {
                    viewModel.loadConfiguration()
                }
                
                Button("Open in Editor") {
                    openInExternalEditor()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func deleteSelectedItem() {
        guard let indexPath = viewModel.selectedItemPath else { return }
        viewModel.deleteMenuItem(at: indexPath)
    }
    
    private func moveItemUp() {
        // TODO: Implement move up
    }
    
    private func moveItemDown() {
        // TODO: Implement move down
    }
    
    private var canMoveUp: Bool {
        // TODO: Check if selected item can move up
        false
    }
    
    private var canMoveDown: Bool {
        // TODO: Check if selected item can move down
        false
    }
    
    private var hasValidationErrors: Bool {
        viewModel.validationErrors.values.contains { errors in
            errors.contains { $0.severity == .error }
        }
    }
    
    private func saveConfiguration() {
        viewModel.saveConfiguration()
        dismiss()
    }
    
    private func openInExternalEditor() {
        let configPath = viewModel.configManager.settingsStore.configFilePath
        if !configPath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        }
    }
    
    private func showDiscardAlert() {
        let alert = NSAlert()
        alert.messageText = "Discard Changes?"
        alert.informativeText = "You have unsaved changes. Do you want to discard them?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.discardChanges()
            dismiss()
        }
    }
}

// MARK: - Preview

struct ConfigEditorView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigEditorView()
    }
}