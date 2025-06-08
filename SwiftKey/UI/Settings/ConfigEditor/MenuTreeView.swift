import SwiftUI
import AppKit

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
        outlineView.usesAlternatingRowBackgroundColors = true
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
        
        // Enable drag and drop (future enhancement)
        // outlineView.registerForDraggedTypes([.menuItem])
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        
        context.coordinator.menuItems = menuItems
        outlineView.reloadData()
        
        // Restore selection if needed
        if let selectedItem = selectedItem,
           let item = context.coordinator.findItem(with: selectedItem.id) {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else {
            outlineView.deselectAll(nil)
        }
        
        // Expand all items by default
        expandAll(outlineView: outlineView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func expandAll(outlineView: NSOutlineView) {
        for i in 0..<outlineView.numberOfRows {
            outlineView.expandItem(outlineView.item(atRow: i))
        }
    }
    
    class Coordinator: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        var parent: MenuTreeView
        var menuItems: [MenuItem] = []
        
        init(_ parent: MenuTreeView) {
            self.parent = parent
            self.menuItems = parent.menuItems
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
        
        // MARK: - Helper Methods
        
        func findItem(with id: UUID) -> MenuItem? {
            func search(in items: [MenuItem]) -> MenuItem? {
                for item in items {
                    if item.id == id {
                        return item
                    }
                    if let found = search(in: item.submenu ?? []) {
                        return found
                    }
                }
                return nil
            }
            return search(in: menuItems)
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
    private let keyLabel = NSTextField()
    private let titleLabel = NSTextField()
    private let stackView = NSStackView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Key label
        keyLabel.isEditable = false
        keyLabel.isBordered = false
        keyLabel.backgroundColor = .clear
        keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .center
        keyLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Title label
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Stack view
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.alignment = .centerY
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(keyLabel)
        stackView.addArrangedSubview(titleLabel)
        
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func configure(with menuItem: MenuItem) {
        // Icon
        if let iconName = menuItem.icon {
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            iconView.contentTintColor = .labelColor
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        
        // Key
        if !menuItem.key.isEmpty {
            keyLabel.stringValue = "[\(menuItem.key)]"
            keyLabel.isHidden = false
        } else {
            keyLabel.isHidden = true
        }
        
        // Title
        titleLabel.stringValue = menuItem.title
        
        // Visual states
        if menuItem.hidden == true {
            titleLabel.textColor = .tertiaryLabelColor
        } else {
            titleLabel.textColor = .labelColor
        }
        
        // Add indicators for special items
        var indicators: [String] = []
        if menuItem.batch == true { indicators.append("⚡") }
        if menuItem.sticky == true { indicators.append("📌") }
        if menuItem.notify == true { indicators.append("🔔") }
        
        if !indicators.isEmpty {
            titleLabel.stringValue = "\(menuItem.title) \(indicators.joined())"
        }
    }
}