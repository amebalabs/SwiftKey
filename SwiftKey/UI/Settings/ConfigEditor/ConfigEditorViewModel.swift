import SwiftUI
import Combine
import os

class ConfigEditorViewModel: ObservableObject {
    @Published var menuItems: [MenuItem] = []
    @Published var selectedItem: MenuItem?
    @Published var selectedItemPath: IndexPath?
    @Published var hasUnsavedChanges = false
    @Published var validationErrors: [UUID: [ValidationError]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    let configManager: ConfigManager
    private let undoManager = UndoManager()
    private var cancellables = Set<AnyCancellable>()
    private var originalItems: [MenuItem] = []
    
    struct ValidationError: Identifiable {
        let id = UUID()
        let field: String
        let message: String
        let severity: Severity
        
        enum Severity {
            case error, warning, info
        }
    }
    
    init(configManager: ConfigManager = .shared) {
        self.configManager = configManager
        loadConfiguration()
    }
    
    func loadConfiguration() {
        isLoading = true
        errorMessage = nil
        
        configManager.loadConfiguration()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        AppLogger.config.error("Failed to load configuration: \(error)")
                    }
                },
                receiveValue: { [weak self] items in
                    self?.menuItems = items
                    self?.originalItems = items
                    self?.hasUnsavedChanges = false
                    self?.validateAll()
                }
            )
            .store(in: &cancellables)
    }
    
    func saveConfiguration() {
        guard hasUnsavedChanges else { return }
        
        isLoading = true
        errorMessage = nil
        
        configManager.saveConfiguration(menuItems)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        AppLogger.config.error("Failed to save configuration: \(error)")
                    }
                },
                receiveValue: { [weak self] in
                    self?.originalItems = self?.menuItems ?? []
                    self?.hasUnsavedChanges = false
                    AppLogger.config.info("Configuration saved successfully")
                }
            )
            .store(in: &cancellables)
    }
    
    func discardChanges() {
        menuItems = originalItems
        hasUnsavedChanges = false
        selectedItem = nil
        selectedItemPath = nil
        validateAll()
    }
    
    // MARK: - Menu Item Operations
    
    func addMenuItem(at indexPath: IndexPath? = nil) {
        let newItem = MenuItem(
            key: "",
            icon: "star",
            title: "New Item",
            action: nil,
            submenu: []
        )
        
        registerUndo()
        
        if let indexPath = indexPath {
            insertMenuItem(newItem, at: indexPath)
        } else {
            menuItems.append(newItem)
        }
        
        hasUnsavedChanges = true
        selectedItem = newItem
        validateAll()
    }
    
    func deleteMenuItem(at indexPath: IndexPath) {
        registerUndo()
        
        if let item = removeMenuItem(at: indexPath) {
            if selectedItem?.id == item.id {
                selectedItem = nil
                selectedItemPath = nil
            }
            hasUnsavedChanges = true
            validateAll()
        }
    }
    
    func updateMenuItem(_ item: MenuItem) {
        registerUndo()
        
        if let indexPath = findIndexPath(for: item) {
            updateMenuItem(item, at: indexPath)
            hasUnsavedChanges = true
            validateItem(item)
        }
    }
    
    func moveMenuItem(from source: IndexPath, to destination: IndexPath) {
        registerUndo()
        
        if let item = removeMenuItem(at: source) {
            insertMenuItem(item, at: destination)
            hasUnsavedChanges = true
            validateAll()
        }
    }
    
    // MARK: - Validation
    
    func validateAll() {
        validationErrors.removeAll()
        validateMenuItems(menuItems, parentPath: [])
    }
    
    func validateItem(_ item: MenuItem) {
        validationErrors[item.id] = validateMenuItem(item)
    }
    
    private func validateMenuItems(_ items: [MenuItem], parentPath: [String]) {
        var seenKeys = Set<String>()
        
        for item in items {
            var errors: [ValidationError] = []
            
            // Key validation
            if item.key.isEmpty {
                errors.append(ValidationError(field: "key", message: "Key is required", severity: .error))
            } else if item.key.count > 1 {
                errors.append(ValidationError(field: "key", message: "Key must be a single character", severity: .error))
            } else if seenKeys.contains(item.key) {
                errors.append(ValidationError(field: "key", message: "Duplicate key at this level", severity: .error))
            } else {
                seenKeys.insert(item.key)
            }
            
            // Title validation
            if item.title.isEmpty {
                errors.append(ValidationError(field: "title", message: "Title is required", severity: .error))
            }
            
            // Action validation
            if let action = item.action {
                errors.append(contentsOf: validateAction(action))
            } else if item.submenu?.isEmpty ?? true {
                errors.append(ValidationError(field: "action", message: "Item must have either an action or submenu", severity: .warning))
            }
            
            // Icon validation
            if let icon = item.icon, !icon.isEmpty {
                // TODO: Validate against SF Symbols list
            }
            
            // Batch validation
            if item.batch == true && (item.submenu?.isEmpty ?? true) {
                errors.append(ValidationError(field: "batch", message: "Batch items must have submenu items", severity: .error))
            }
            
            validationErrors[item.id] = errors.isEmpty ? nil : errors
            
            // Validate submenu
            if let submenu = item.submenu {
                validateMenuItems(submenu, parentPath: parentPath + [item.key])
            }
        }
    }
    
    private func validateMenuItem(_ item: MenuItem) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        if item.key.isEmpty {
            errors.append(ValidationError(field: "key", message: "Key is required", severity: .error))
        } else if item.key.count > 1 {
            errors.append(ValidationError(field: "key", message: "Key must be a single character", severity: .error))
        }
        
        if item.title.isEmpty {
            errors.append(ValidationError(field: "title", message: "Title is required", severity: .error))
        }
        
        if let action = item.action {
            errors.append(contentsOf: validateAction(action))
        }
        
        return errors
    }
    
    private func validateAction(_ action: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        if action.hasPrefix("launch://") {
            let path = String(action.dropFirst("launch://".count))
            let expandedPath = (path as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: expandedPath) {
                errors.append(ValidationError(field: "action", message: "Application not found", severity: .error))
            }
        } else if action.hasPrefix("open://") {
            let urlString = String(action.dropFirst("open://".count))
            if URL(string: urlString) == nil {
                errors.append(ValidationError(field: "action", message: "Invalid URL format", severity: .error))
            }
        } else if action.hasPrefix("shell://") {
            let command = String(action.dropFirst("shell://".count))
            if command.contains("rm ") || command.contains("sudo") {
                errors.append(ValidationError(field: "action", message: "Potentially dangerous command", severity: .warning))
            }
        } else if action.hasPrefix("dynamic://") {
            let scriptPath = String(action.dropFirst("dynamic://".count))
            let expandedPath = (scriptPath as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: expandedPath) {
                errors.append(ValidationError(field: "action", message: "Script not found", severity: .error))
            }
        }
        
        return errors
    }
    
    // MARK: - Undo/Redo
    
    private func registerUndo() {
        let currentItems = menuItems
        undoManager.registerUndo(withTarget: self) { target in
            target.menuItems = currentItems
            target.hasUnsavedChanges = true
            target.validateAll()
        }
    }
    
    func undo() {
        undoManager.undo()
    }
    
    func redo() {
        undoManager.redo()
    }
    
    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }
    
    // MARK: - Helper Methods
    
    private func findIndexPath(for item: MenuItem) -> IndexPath? {
        func search(in items: [MenuItem], currentPath: [Int]) -> IndexPath? {
            for (index, menuItem) in items.enumerated() {
                if menuItem.id == item.id {
                    return IndexPath(indexes: currentPath + [index])
                }
                if let submenu = menuItem.submenu,
                   let found = search(in: submenu, currentPath: currentPath + [index]) {
                    return found
                }
            }
            return nil
        }
        return search(in: menuItems, currentPath: [])
    }
    
    private func menuItem(at indexPath: IndexPath) -> MenuItem? {
        var current = menuItems
        for (offset, index) in indexPath.enumerated() {
            guard index < current.count else { return nil }
            if offset == indexPath.count - 1 {
                return current[index]
            }
            current = current[index].submenu ?? []
        }
        return nil
    }
    
    private func removeMenuItem(at indexPath: IndexPath) -> MenuItem? {
        var current = menuItems
        var parents: [(items: [MenuItem], index: Int)] = []
        
        for (offset, index) in indexPath.enumerated() {
            guard index < current.count else { return nil }
            
            if offset == indexPath.count - 1 {
                let removed = current.remove(at: index)
                
                // Update the tree
                if parents.isEmpty {
                    menuItems = current
                } else {
                    // Rebuild the tree with the modification
                    rebuildTree(parents: parents, newItems: current)
                }
                
                return removed
            }
            
            parents.append((items: current, index: index))
            current = current[index].submenu ?? []
        }
        
        return nil
    }
    
    private func insertMenuItem(_ item: MenuItem, at indexPath: IndexPath) {
        if indexPath.isEmpty {
            menuItems.append(item)
            return
        }
        
        var current = menuItems
        var parents: [(items: [MenuItem], index: Int)] = []
        
        for (offset, index) in indexPath.enumerated() {
            if offset == indexPath.count - 1 {
                current.insert(item, at: min(index, current.count))
                
                // Update the tree
                if parents.isEmpty {
                    menuItems = current
                } else {
                    rebuildTree(parents: parents, newItems: current)
                }
                return
            }
            
            guard index < current.count else { return }
            parents.append((items: current, index: index))
            
            var menuItem = current[index]
            if menuItem.submenu == nil {
                menuItem.submenu = []
            }
            current = menuItem.submenu ?? []
        }
    }
    
    private func updateMenuItem(_ item: MenuItem, at indexPath: IndexPath) {
        var current = menuItems
        var parents: [(items: [MenuItem], index: Int)] = []
        
        for (offset, index) in indexPath.enumerated() {
            guard index < current.count else { return }
            
            if offset == indexPath.count - 1 {
                current[index] = item
                
                // Update the tree
                if parents.isEmpty {
                    menuItems = current
                } else {
                    rebuildTree(parents: parents, newItems: current)
                }
                return
            }
            
            parents.append((items: current, index: index))
            current = current[index].submenu ?? []
        }
    }
    
    private func rebuildTree(parents: [(items: [MenuItem], index: Int)], newItems: [MenuItem]) {
        var current = newItems
        
        for (parentItems, parentIndex) in parents.reversed() {
            var updatedParent = parentItems
            var parentItem = updatedParent[parentIndex]
            parentItem.submenu = current
            updatedParent[parentIndex] = parentItem
            current = updatedParent
        }
        
        menuItems = current
    }
}