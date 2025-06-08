import SwiftUI
import Yams
import UniformTypeIdentifiers

extension UTType {
    static var yaml: UTType {
        UTType(importedAs: "public.yaml")
    }
}

struct ConfigEditorView: View {
    @StateObject private var viewModel: ConfigEditorViewModel
    @State private var showingImportDialog = false
    @State private var showingValidationPanel = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var configManager: ConfigManager
    
    init(configManager: ConfigManager? = nil) {
        _viewModel = StateObject(wrappedValue: ConfigEditorViewModel(configManager: configManager ?? ConfigManager()))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content using base view
            ConfigEditorBaseView(
                viewModel: viewModel,
                showingImportDialog: $showingImportDialog,
                showingValidationPanel: $showingValidationPanel
            )
            
            Divider()
            
            // Footer with action buttons
            footerView
        }
        .frame(width: 900, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.loadConfiguration()
        }
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
            .fileImporter(
                isPresented: $showingImportDialog,
                allowedContentTypes: [.yaml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importConfiguration(from: url)
                    }
                case .failure(let error):
                    AppLogger.config.error("Failed to import configuration: \(error)")
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            
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
    
    // MARK: - Actions
    
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
    
    private func importConfiguration(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            viewModel.errorMessage = "Cannot access the selected file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            let decoder = YAMLDecoder()
            let menuItems = try decoder.decode([MenuItem].self, from: yamlString)
            
            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "Import Configuration?"
            alert.informativeText = "This will replace your current configuration with the imported one. Your current configuration will be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Import")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                viewModel.menuItems = menuItems
                viewModel.hasUnsavedChanges = true
                viewModel.validateAll()
                AppLogger.config.info("Configuration imported from \(url.lastPathComponent)")
            }
        } catch {
            viewModel.errorMessage = "Failed to import configuration: \(error.localizedDescription)"
            AppLogger.config.error("Failed to import configuration from \(url): \(error)")
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