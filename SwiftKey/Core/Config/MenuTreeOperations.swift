import Foundation

/// Handles tree manipulation operations for menu items
enum MenuTreeOperations {

    /// Finds the index path to an item with the given ID
    static func findIndexPath(for id: UUID, in items: [MenuItem], currentPath: [Int] = []) -> [Int]? {
        for (index, item) in items.enumerated() {
            let path = currentPath + [index]

            if item.id == id {
                return path
            }

            if let submenu = item.submenu,
               let foundPath = findIndexPath(for: id, in: submenu, currentPath: path) {
                return foundPath
            }
        }

        return nil
    }

    /// Gets the menu item at the given index path
    static func item(at indexPath: [Int], in items: [MenuItem]) -> MenuItem? {
        guard !indexPath.isEmpty else { return nil }

        var current = items
        var result: MenuItem?

        for (depth, index) in indexPath.enumerated() {
            guard index >= 0, index < current.count else { return nil }

            result = current[index]

            if depth < indexPath.count - 1 {
                guard let submenu = current[index].submenu else { return nil }
                current = submenu
            }
        }

        return result
    }

    /// Gets the parent item for a given index path
    static func parent(of indexPath: [Int], in items: [MenuItem]) -> MenuItem? {
        guard indexPath.count > 1 else { return nil }
        let parentPath = Array(indexPath.dropLast())
        return item(at: parentPath, in: items)
    }

    /// Gets sibling items at the same level
    static func siblings(of indexPath: [Int], in items: [MenuItem]) -> [MenuItem] {
        guard !indexPath.isEmpty else { return items }

        if indexPath.count == 1 {
            return items
        }

        let parentPath = Array(indexPath.dropLast())
        if let parent = item(at: parentPath, in: items) {
            return parent.submenu ?? []
        }

        return []
    }

    /// Inserts an item at the given index path
    static func insert(_ newItem: MenuItem, at indexPath: [Int], in items: inout [MenuItem]) {
        guard !indexPath.isEmpty else { return }

        if indexPath.count == 1 {
            let index = min(max(0, indexPath[0]), items.count)
            items.insert(newItem, at: index)
        } else {
            let parentIndex = indexPath[0]
            guard parentIndex >= 0, parentIndex < items.count else { return }

            var submenu = items[parentIndex].submenu ?? []
            let remainingPath = Array(indexPath.dropFirst())
            insert(newItem, at: remainingPath, in: &submenu)
            items[parentIndex].submenu = submenu
        }
    }

    /// Appends an item to the end of the specified level
    static func append(_ newItem: MenuItem, toParentAt parentPath: [Int]?, in items: inout [MenuItem]) {
        if let parentPath = parentPath, !parentPath.isEmpty {
            guard var parent = item(at: parentPath, in: items) else { return }
            var submenu = parent.submenu ?? []
            submenu.append(newItem)
            parent.submenu = submenu
            update(parent, at: parentPath, in: &items)
        } else {
            items.append(newItem)
        }
    }

    /// Removes the item at the given index path
    @discardableResult
    static func remove(at indexPath: [Int], from items: inout [MenuItem]) -> MenuItem? {
        guard !indexPath.isEmpty else { return nil }

        if indexPath.count == 1 {
            let index = indexPath[0]
            guard index >= 0, index < items.count else { return nil }
            return items.remove(at: index)
        } else {
            let parentIndex = indexPath[0]
            guard parentIndex >= 0, parentIndex < items.count else { return nil }

            var submenu = items[parentIndex].submenu ?? []
            let remainingPath = Array(indexPath.dropFirst())
            let removed = remove(at: remainingPath, from: &submenu)
            items[parentIndex].submenu = submenu.isEmpty ? nil : submenu
            return removed
        }
    }

    /// Moves an item from one index path to another
    static func move(from sourcePath: [Int], to destinationPath: [Int], in items: inout [MenuItem]) -> Bool {
        guard let item = remove(at: sourcePath, from: &items) else { return false }

        // Adjust destination if it was affected by removal
        var adjustedDestination = destinationPath

        // If moving within the same parent and destination is after source
        if sourcePath.dropLast() == destinationPath.dropLast() {
            if let srcLast = sourcePath.last, let dstLast = destinationPath.last {
                if dstLast > srcLast {
                    adjustedDestination[adjustedDestination.count - 1] = dstLast - 1
                }
            }
        }

        insert(item, at: adjustedDestination, in: &items)
        return true
    }

    /// Updates the item at the given index path
    static func update(_ updatedItem: MenuItem, at indexPath: [Int], in items: inout [MenuItem]) {
        guard !indexPath.isEmpty else { return }

        if indexPath.count == 1 {
            let index = indexPath[0]
            guard index >= 0, index < items.count else { return }
            items[index] = updatedItem
        } else {
            let parentIndex = indexPath[0]
            guard parentIndex >= 0, parentIndex < items.count else { return }

            var submenu = items[parentIndex].submenu ?? []
            let remainingPath = Array(indexPath.dropFirst())
            update(updatedItem, at: remainingPath, in: &submenu)
            items[parentIndex].submenu = submenu
        }
    }

    /// Flattens the tree into a list of all items
    static func flatten(_ items: [MenuItem]) -> [MenuItem] {
        var result: [MenuItem] = []
        for item in items {
            result.append(item)
            if let submenu = item.submenu {
                result.append(contentsOf: flatten(submenu))
            }
        }
        return result
    }

    /// Counts total items including submenus
    static func totalCount(_ items: [MenuItem]) -> Int {
        flatten(items).count
    }

    /// Finds an item by ID
    static func find(id: UUID, in items: [MenuItem]) -> MenuItem? {
        for item in items {
            if item.id == id {
                return item
            }
            if let submenu = item.submenu, let found = find(id: id, in: submenu) {
                return found
            }
        }
        return nil
    }
}
