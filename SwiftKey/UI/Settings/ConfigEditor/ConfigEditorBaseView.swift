import SwiftUI

/// Base view containing shared functionality for config editor
struct ConfigEditorBaseView: View {
    @ObservedObject var viewModel: ConfigEditorViewModel
    @Binding var showingImportDialog: Bool
    @Binding var showingValidationPanel: Bool
    
    var body: some View {
        Group {
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
                
                // Modified indicator
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
                
                if !viewModel.validationErrors.isEmpty {
                    validationIndicator
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
    
    // MARK: - Validation Indicator
    
    private var validationIndicator: some View {
        let errorCount = viewModel.validationErrors.values.flatMap { $0 }.filter { $0.severity == .error }.count
        let warningCount = viewModel.validationErrors.values.flatMap { $0 }.filter { $0.severity == .warning }.count
        
        return Button(action: { showingValidationPanel.toggle() }) {
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
        guard let indexPath = viewModel.selectedItemPath else { return }
        let currentIndex = indexPath[indexPath.count - 1]
        guard currentIndex > 0 else { return }
        
        var newIndexPath = indexPath
        newIndexPath[indexPath.count - 1] = currentIndex - 1
        viewModel.moveMenuItem(from: indexPath, to: newIndexPath)
    }
    
    private func moveItemDown() {
        guard let indexPath = viewModel.selectedItemPath else { return }
        let currentIndex = indexPath[indexPath.count - 1]
        
        // Get parent items to check bounds
        var parentItems = viewModel.menuItems
        for i in 0..<(indexPath.count - 1) {
            guard indexPath[i] < parentItems.count,
                  let submenu = parentItems[indexPath[i]].submenu else { return }
            parentItems = submenu
        }
        
        guard currentIndex < parentItems.count - 1 else { return }
        
        var newIndexPath = indexPath
        newIndexPath[indexPath.count - 1] = currentIndex + 1
        viewModel.moveMenuItem(from: indexPath, to: newIndexPath)
    }
    
    private var canMoveUp: Bool {
        guard let indexPath = viewModel.selectedItemPath else { return false }
        return indexPath[indexPath.count - 1] > 0
    }
    
    private var canMoveDown: Bool {
        guard let indexPath = viewModel.selectedItemPath else { return false }
        let currentIndex = indexPath[indexPath.count - 1]
        
        // Get parent items to check bounds
        var parentItems = viewModel.menuItems
        for i in 0..<(indexPath.count - 1) {
            guard indexPath[i] < parentItems.count,
                  let submenu = parentItems[indexPath[i]].submenu else { return false }
            parentItems = submenu
        }
        
        return currentIndex < parentItems.count - 1
    }
    
    var hasValidationErrors: Bool {
        viewModel.validationErrors.values.contains { errors in
            errors.contains { $0.severity == .error }
        }
    }
    
    func saveConfiguration() {
        viewModel.saveConfiguration()
    }
    
    func openInExternalEditor() {
        let configPath = viewModel.configManager.settingsStore.configFilePath
        if !configPath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        }
    }
}