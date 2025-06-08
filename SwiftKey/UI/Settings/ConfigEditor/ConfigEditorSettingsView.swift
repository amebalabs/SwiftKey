import SwiftUI

struct ConfigEditorSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @StateObject private var viewModel: ConfigEditorViewModel
    @State private var showingImportDialog = false
    @State private var showingValidationPanel = false
    
    init() {
        _viewModel = StateObject(wrappedValue: ConfigEditorViewModel())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            HStack {
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
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    if viewModel.hasUnsavedChanges {
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
                        
                        Divider()
                            .frame(height: 16)
                    }
                    
                    Button("Open in Editor") {
                        openInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open the YAML file in your default text editor")
                    
                    Button("Import...") {
                        showingImportDialog = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Import configuration from file")
                    
                    if viewModel.hasUnsavedChanges {
                        Button("Discard") {
                            viewModel.discardChanges()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Save") {
                            saveConfiguration()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(hasValidationErrors)
                        .help(hasValidationErrors ? "Fix validation errors before saving" : "Save changes")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Main content
            if viewModel.isLoading {
                ProgressView("Loading configuration...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else {
                HSplitView {
                    // Menu tree
                    menuTreePanel
                        .frame(minWidth: 250, idealWidth: 350, maxWidth: 400)
                    
                    // Property inspector
                    propertyInspectorPanel
                        .frame(minWidth: 400, idealWidth: 550)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 900, idealHeight: 650)
        .onAppear {
            // Set the config manager from environment
            viewModel.configManager = configManager
            viewModel.loadConfiguration()
        }
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
                    let errorCount = viewModel.validationErrors.values.flatMap { $0 }.filter { $0.severity == .error }.count
                    let warningCount = viewModel.validationErrors.values.flatMap { $0 }.filter { $0.severity == .warning }.count
                    
                    Button(action: { showingValidationPanel.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(errorCount > 0 ? .red : .orange)
                                .font(.caption)
                            Text("\(errorCount > 0 ? "\(errorCount)" : "")\(errorCount > 0 && warningCount > 0 ? "/" : "")\(warningCount > 0 ? "\(warningCount)" : "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Click to see validation issues")
                    .popover(isPresented: $showingValidationPanel) {
                        ValidationIssuesView(validationErrors: viewModel.validationErrors, menuItems: viewModel.menuItems)
                            .frame(width: 400, height: 300)
                    }
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
    }
    
    private func openInExternalEditor() {
        let configPath = viewModel.configManager.settingsStore.configFilePath
        if !configPath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        }
    }
}

// MARK: - Preview

struct ConfigEditorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigEditorSettingsView()
            .frame(width: 700, height: 500)
    }
}