import SwiftUI
import Yams
import UniformTypeIdentifiers

struct ConfigEditorSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var approvalGate: ApprovalGate
    @State private var showingImportDialog = false
    @State private var showingValidationPanel = false
    
    var body: some View {
        ConfigEditorSettingsContent(
            configManager: configManager,
            settings: settings,
            approvalGate: approvalGate,
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
    
    init(configManager: ConfigManager, settings: SettingsStore, approvalGate: ApprovalGate, showingImportDialog: Binding<Bool>,
         showingValidationPanel: Binding<Bool>) {
        self.configManager = configManager
        self.settings = settings
        self._showingImportDialog = showingImportDialog
        self._showingValidationPanel = showingValidationPanel
        self._viewModel = StateObject(wrappedValue: ConfigEditorViewModel(configManager: configManager, approvalGate: approvalGate))
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
            
            // Bottom bar: the config file on the left, editing actions on the right
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                if let url = configManager.resolveConfigFileURL() {
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                } else {
                    Text("No config file selected")
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button("Show in Finder") {
                        configManager.openConfigFile()
                    }
                    Button("Open in Editor") {
                        openInExternalEditor()
                    }
                    Divider()
                    Button("Choose Another File…") {
                        configManager.changeConfigFile()
                    }
                    Button("Import…") {
                        showingImportDialog = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Configuration file actions")
                .accessibilityLabel("Configuration file actions")

                Spacer(minLength: 16)

                if viewModel.hasUnsavedChanges {
                    ControlGroup {
                        Button(action: viewModel.undo) {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!viewModel.canUndo)
                        .help("Undo")
                        .accessibilityLabel("Undo")

                        Button(action: viewModel.redo) {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!viewModel.canRedo)
                        .help("Redo")
                        .accessibilityLabel("Redo")
                    }
                    .fixedSize()

                    Button("Discard") {
                        viewModel.discardChanges()
                    }

                    Button("Save") {
                        viewModel.saveConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(hasValidationErrors)
                    .help(hasValidationErrors ? "Fix validation errors before saving" : "Save changes")
                } else {
                    Button("Open in Editor") {
                        openInExternalEditor()
                    }
                    .help("Open the YAML file in your default text editor")
                }
            }
            .font(.callout)
            .controlSize(.regular)
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
