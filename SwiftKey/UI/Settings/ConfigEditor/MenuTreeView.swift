import SwiftUI
import AppKit
import SwiftKeyCore

extension NSPasteboard.PasteboardType {
    static let menuItem = NSPasteboard.PasteboardType("com.swiftkey.menuitem")
}

struct MenuTreeView: NSViewRepresentable {
    @Binding var menuItems: [MenuItem]
    @Binding var selectedItem: MenuItem?
    @Binding var selectedItemPath: IndexPath?
    let onDelete: (IndexPath) -> Void
    let onMove: (IndexPath, IndexPath) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        
        let outlineView = NSOutlineView()
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.style = .inset
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 16
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.headerView = nil
        
        // Create single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MenuItemColumn"))
        column.title = "Menu Items"
        column.isEditable = false
        column.minWidth = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        // Enable drag and drop
        outlineView.registerForDraggedTypes([.menuItem])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        
        let oldSelectedId = context.coordinator.selectedItem?.id
        let newSelectedId = selectedItem?.id
        
        // Check if the menu structure has changed
        let menuStructureChanged = !areMenuItemsEqual(context.coordinator.menuItems, menuItems)
        
        // Check if this is just a property update of the same item
        let isPropertyUpdate = oldSelectedId == newSelectedId && 
                             oldSelectedId != nil &&
                             !menuStructureChanged
        
        context.coordinator.menuItems = menuItems
        context.coordinator.selectedItem = selectedItem
        
        if isPropertyUpdate {
            // Just update the visible cells without reloading
            if let item = context.coordinator.findItem(with: newSelectedId!) {
                let row = outlineView.row(forItem: item)
                if row >= 0 {
                    outlineView.reloadData(forRowIndexes: IndexSet(integer: row), 
                                         columnIndexes: IndexSet(integer: 0))
                }
            }
        } else {
            // Save expansion state before reload
            var expandedItems = Set<UUID>()
            for i in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: i) as? MenuItem,
                   outlineView.isItemExpanded(item) {
                    expandedItems.insert(item.id)
                }
            }
            
            outlineView.reloadData()
            
            // Restore expansion state
            for i in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: i) as? MenuItem,
                   expandedItems.contains(item.id) {
                    outlineView.expandItem(item)
                }
            }
            
            // Only expand all on first load
            if !context.coordinator.hasInitialized {
                context.coordinator.hasInitialized = true
                expandAll(outlineView: outlineView)
            }
        }
        
        // Restore selection if needed
        if let selectedItem = selectedItem,
           let item = context.coordinator.findItem(with: selectedItem.id) {
            let row = outlineView.row(forItem: item)
            if row >= 0 && outlineView.selectedRow != row {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else {
            outlineView.deselectAll(nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func expandAll(outlineView: NSOutlineView) {
        for i in 0..<outlineView.numberOfRows {
            outlineView.expandItem(outlineView.item(atRow: i))
        }
    }
    
    private func areMenuItemsEqual(_ items1: [MenuItem], _ items2: [MenuItem]) -> Bool {
        guard items1.count == items2.count else { return false }
        
        for (index, item1) in items1.enumerated() {
            let item2 = items2[index]
            // Check if items are in the same order
            if item1.id != item2.id {
                return false
            }
            // Recursively check submenus
            if let submenu1 = item1.submenu, let submenu2 = item2.submenu {
                if !areMenuItemsEqual(submenu1, submenu2) {
                    return false
                }
            } else if (item1.submenu != nil) != (item2.submenu != nil) {
                return false
            }
        }
        
        return true
    }
    
    class Coordinator: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        var parent: MenuTreeView
        var menuItems: [MenuItem] = []
        var selectedItem: MenuItem?
        var hasInitialized = false
        
        init(_ parent: MenuTreeView) {
            self.parent = parent
            self.menuItems = parent.menuItems
            self.selectedItem = parent.selectedItem
        }
        
        // MARK: - NSOutlineViewDataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let menuItem = item as? MenuItem {
                return menuItem.submenu?.count ?? 0
            }
            return menuItems.count
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let menuItem = item as? MenuItem {
                return menuItem.submenu?[index] ?? MenuItem(key: "", title: "Error")
            }
            return menuItems[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if let menuItem = item as? MenuItem {
                return !(menuItem.submenu?.isEmpty ?? true)
            }
            return false
        }
        
        // MARK: - NSOutlineViewDelegate
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let menuItem = item as? MenuItem else { return nil }
            
            let cellIdentifier = NSUserInterfaceItemIdentifier("MenuItemCell")
            
            let cell: MenuItemCellView
            if let recycled = outlineView.makeView(withIdentifier: cellIdentifier, owner: nil) as? MenuItemCellView {
                cell = recycled
            } else {
                cell = MenuItemCellView()
                cell.identifier = cellIdentifier
            }
            
            cell.configure(with: menuItem)
            return cell
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            
            let selectedRow = outlineView.selectedRow
            if selectedRow >= 0,
               let item = outlineView.item(atRow: selectedRow) as? MenuItem {
                parent.selectedItem = item
                parent.selectedItemPath = indexPath(for: item, in: menuItems)
            } else {
                parent.selectedItem = nil
                parent.selectedItemPath = nil
            }
        }
        
        // MARK: - Drag and Drop
        
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let menuItem = item as? MenuItem else { return nil }
            
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(menuItem.id.uuidString, forType: .menuItem)
            return pasteboardItem
        }
        
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            // Can't drop on itself
            if let draggedItemId = info.draggingPasteboard.string(forType: .menuItem),
               let draggedItem = findItem(with: UUID(uuidString: draggedItemId) ?? UUID()),
               let targetItem = item as? MenuItem,
               draggedItem.id == targetItem.id {
                return []
            }
            
            // Allow drops between items and on items (to create submenus)
            return .move
        }
        
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let draggedItemId = info.draggingPasteboard.string(forType: .menuItem),
                  let draggedItemUUID = UUID(uuidString: draggedItemId),
                  let sourceIndexPath = indexPath(for: draggedItemUUID, in: menuItems) else {
                return false
            }
            
            // Calculate destination index path
            let destinationIndexPath: IndexPath
            
            if let targetItem = item as? MenuItem {
                // Dropping on an item - add as child
                if let targetPath = indexPath(for: targetItem, in: menuItems) {
                    if index == NSOutlineViewDropOnItemIndex {
                        // Drop on item - add as last child
                        let childCount = targetItem.submenu?.count ?? 0
                        destinationIndexPath = IndexPath(indexes: targetPath.map { $0 } + [childCount])
                    } else {
                        // Drop between children
                        destinationIndexPath = IndexPath(indexes: targetPath.map { $0 } + [index])
                    }
                } else {
                    return false
                }
            } else {
                // Dropping at root level
                if index == NSOutlineViewDropOnItemIndex {
                    destinationIndexPath = IndexPath(index: menuItems.count)
                } else {
                    destinationIndexPath = IndexPath(index: index)
                }
            }
            
            // Don't allow dropping an item into its own descendants
            if isDescendant(sourceIndexPath, of: destinationIndexPath) {
                return false
            }
            
            // Adjust destination if it comes after source at the same level
            var adjustedDestination = destinationIndexPath
            if sourceIndexPath.count == destinationIndexPath.count {
                let sourceParent = Array(sourceIndexPath.dropLast())
                let destParent = Array(destinationIndexPath.dropLast())
                
                if sourceParent == destParent {
                    let sourceIndex = sourceIndexPath[sourceIndexPath.count - 1]
                    let destIndex = destinationIndexPath[destinationIndexPath.count - 1]
                    
                    if sourceIndex < destIndex {
                        adjustedDestination = IndexPath(indexes: destParent + [destIndex - 1])
                    }
                }
            }
            
            // Perform the move
            parent.onMove(sourceIndexPath, adjustedDestination)
            
            return true
        }
        
        private func isDescendant(_ path: IndexPath, of possibleAncestor: IndexPath) -> Bool {
            guard path.count < possibleAncestor.count else { return false }
            
            for i in 0..<path.count {
                if path[i] != possibleAncestor[i] {
                    return false
                }
            }
            
            return true
        }
        
        // MARK: - Helper Methods
        
        func findItem(with id: UUID) -> MenuItem? {
            return menuItems.findItem(with: id)
        }
        
        func indexPath(for itemId: UUID, in items: [MenuItem], currentPath: [Int] = []) -> IndexPath? {
            for (index, item) in items.enumerated() {
                if item.id == itemId {
                    return IndexPath(indexes: currentPath + [index])
                }
                if let submenu = item.submenu,
                   let found = indexPath(for: itemId, in: submenu, currentPath: currentPath + [index]) {
                    return found
                }
            }
            return nil
        }
        
        func indexPath(for targetItem: MenuItem, in items: [MenuItem], currentPath: [Int] = []) -> IndexPath? {
            for (index, item) in items.enumerated() {
                if item.id == targetItem.id {
                    return IndexPath(indexes: currentPath + [index])
                }
                if let submenu = item.submenu,
                   let found = indexPath(for: targetItem, in: submenu, currentPath: currentPath + [index]) {
                    return found
                }
            }
            return nil
        }
    }
}

// MARK: - Menu Item Cell View

class MenuItemCellView: NSView {
    private let iconView = NSImageView()
    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let flagsView = NSStackView()
    private let stackView = NSStackView()

    /// Width of the key column, so titles line up whatever the key ("a", "space", "f12").
    private static let keyWidth: CGFloat = 40

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Icon: always takes its slot, so items with and without an icon line up.
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Key, drawn as a small keycap.
        keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .center
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.wantsLayer = true
        keyLabel.layer?.cornerRadius = 4
        keyLabel.layer?.borderWidth = 1
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Flags: sticky, batch, notify, hidden as small symbols after the title.
        flagsView.orientation = .horizontal
        flagsView.spacing = 3
        flagsView.setContentHuggingPriority(.required, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.alignment = .centerY
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(keyLabel)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(flagsView)

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            keyLabel.widthAnchor.constraint(equalToConstant: Self.keyWidth),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateKeycapColors()
    }

    private func updateKeycapColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            keyLabel.layer?.borderColor = NSColor.separatorColor.cgColor
            keyLabel.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        }
    }

    func configure(with menuItem: MenuItem) {
        // Icon
        if let iconName = menuItem.icon {
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            iconView.contentTintColor = .labelColor
        } else {
            iconView.image = nil
        }

        // Key, shown as the menu shows it: "␣" for space, "F5" for f5.
        let key = SequenceKey.normalize(menuItem.key).map(SequenceKey.display) ?? menuItem.key
        keyLabel.stringValue = key
        keyLabel.isHidden = menuItem.key.isEmpty
        keyLabel.toolTip = menuItem.key.isEmpty ? nil : "Key: \(menuItem.key)"
        updateKeycapColors()

        // Title
        titleLabel.stringValue = menuItem.title
        titleLabel.textColor = menuItem.hidden == true ? .tertiaryLabelColor : .labelColor

        // Flags
        flagsView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let flags: [(Bool?, String, String)] = [
            (menuItem.batch, "bolt.fill", "Batch"),
            (menuItem.sticky, "pin.fill", "Sticky"),
            (menuItem.notify, "bell.fill", "Notify"),
            (menuItem.hidden, "eye.slash", "Hidden"),
        ]
        for (isOn, symbol, name) in flags where isOn == true {
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage())
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            image.contentTintColor = .tertiaryLabelColor
            image.toolTip = name
            flagsView.addArrangedSubview(image)
        }

        setAccessibilityLabel([menuItem.key.isEmpty ? nil : "Key \(menuItem.key)", menuItem.title]
            .compactMap { $0 }.joined(separator: ", "))
    }
}
