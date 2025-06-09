import SwiftUI
import Yams
import UniformTypeIdentifiers

struct ConfigEditorSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var settings: SettingsStore
    @State private var showingImportDialog = false
    @State private var showingValidationPanel = false
    
    var body: some View {
        ConfigEditorSettingsContent(
            configManager: configManager,
            settings: settings,
            showingImportDialog: $showingImportDialog,
            showingValidationPanel: $showingValidationPanel
        )
    }
}

// Internal view that can properly initialize the view model with the config manager
private struct ConfigEditorSettingsContent: View {
    let configManager: ConfigManager
    let settings: SettingsStore
    @Binding var showingImportDialog: Bool
    @Binding var showingValidationPanel: Bool
    @StateObject private var viewModel: ConfigEditorViewModel
    
    init(configManager: ConfigManager, settings: SettingsStore, showingImportDialog: Binding<Bool>, showingValidationPanel: Binding<Bool>) {
        self.configManager = configManager
        self.settings = settings
        self._showingImportDialog = showingImportDialog
        self._showingValidationPanel = showingValidationPanel
        self._viewModel = StateObject(wrappedValue: ConfigEditorViewModel(configManager: configManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Show configuration error if present
            if let error = configManager.lastError {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Configuration Error")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let configError = error as? ConfigError,
                       case let .invalidYamlFormat(_, line, column) = configError,
                       line > 0
                    {
                        Text("Line \(line), Column \(column)")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }

                    HStack {
                        Button("Reload Configuration") {
                            Task {
                                await configManager.loadConfig()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Edit File") {
                            configManager.openConfigFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 5)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding()
            } else if configManager.menuItems.isEmpty {
                Text("No menu items loaded. Please check your configuration file.")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .padding()
            }
            
            // Main content using base view
            ConfigEditorBaseView(
                viewModel: viewModel,
                showingImportDialog: $showingImportDialog,
                showingValidationPanel: $showingValidationPanel
            )
            
            Divider()
            
            // Bottom toolbar with config path and buttons
            VStack(spacing: 8) {
                // Config file path section
                HStack(spacing: 8) {
                    Text("Configuration file:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if !settings.configFilePath.isEmpty {
                        if let url = configManager.resolveConfigFileURL() {
                            Text(url.path)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("No config file selected")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        configManager.openConfigFile()
                    }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Reveal configuration file in Finder")
                    
                    Button("Change...") {
                        configManager.changeConfigFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                }
                
                // Action buttons
                HStack {
                    Spacer()
                    
                    // Buttons aligned to the right
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
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
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
        viewModel.importConfiguration(from: url) { success in
            if success {
                // Show confirmation dialog
                let alert = NSAlert()
                alert.messageText = "Import Configuration?"
                alert.informativeText = "This will replace your current configuration with the imported one. Your current configuration will be lost."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    viewModel.confirmImport()
                }
            }
        }
    }
}

// MARK: - Preview

struct ConfigEditorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigEditorSettingsView()
            .frame(width: 700, height: 500)
            .environmentObject(SettingsStore())
            .environmentObject(ConfigManager.create())
    }
}
