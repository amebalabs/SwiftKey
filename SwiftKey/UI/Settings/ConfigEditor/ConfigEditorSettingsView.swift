import SwiftUI
import Yams
import UniformTypeIdentifiers

struct ConfigEditorSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @StateObject private var viewModel: ConfigEditorViewModel
    @State private var showingImportDialog = false
    @State private var showingValidationPanel = false
    
    init(configManager: ConfigManager? = nil) {
        _viewModel = StateObject(wrappedValue: ConfigEditorViewModel(configManager: configManager ?? ConfigManager()))
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
                            viewModel.saveConfiguration()
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
            
            // Main content using base view
            ConfigEditorBaseView(
                viewModel: viewModel,
                showingImportDialog: $showingImportDialog,
                showingValidationPanel: $showingValidationPanel
            )
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 900, idealHeight: 650)
        .onAppear {
            viewModel.loadConfiguration()
        }
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
    }
    
    // MARK: - Actions
    
    private var hasValidationErrors: Bool {
        viewModel.validationErrors.values.contains { errors in
            errors.contains { $0.severity == .error }
        }
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
}

// MARK: - Preview

struct ConfigEditorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigEditorSettingsView()
            .frame(width: 700, height: 500)
    }
}