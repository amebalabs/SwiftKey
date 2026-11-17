import Testing
import Foundation
@testable import SwiftKey

@Suite("Menu Tree Operations")
struct MenuTreeOperationsTests {

    // MARK: - Test Fixtures

    func createTestItem(key: String, title: String, submenu: [MenuItem]? = nil) -> MenuItem {
        MenuItem(
            id: UUID(),
            key: key,
            icon: nil,
            title: title,
            action: submenu == nil ? "open://test" : nil,
            sticky: false,
            notify: false,
            batch: false,
            hidden: false,
            submenu: submenu,
            hotkey: nil
        )
    }

    func createTestTree() -> [MenuItem] {
        let subSubItem = createTestItem(key: "x", title: "SubSub Item")
        let subItem1 = createTestItem(key: "1", title: "Sub Item 1")
        let subItem2 = createTestItem(key: "2", title: "Sub Item 2", submenu: [subSubItem])

        return [
            createTestItem(key: "a", title: "Item A", submenu: [subItem1, subItem2]),
            createTestItem(key: "b", title: "Item B"),
            createTestItem(key: "c", title: "Item C")
        ]
    }

    // MARK: - Find Index Path Tests

    @Test("Find index path for root item")
    func findIndexPathRootItem() {
        let items = createTestTree()
        let targetId = items[1].id

        let path = MenuTreeOperations.findIndexPath(for: targetId, in: items)

        #expect(path == [1])
    }

    @Test("Find index path for nested item")
    func findIndexPathNestedItem() {
        let items = createTestTree()
        let targetId = items[0].submenu![0].id

        let path = MenuTreeOperations.findIndexPath(for: targetId, in: items)

        #expect(path == [0, 0])
    }

    @Test("Find index path for deeply nested item")
    func findIndexPathDeeplyNestedItem() {
        let items = createTestTree()
        let targetId = items[0].submenu![1].submenu![0].id

        let path = MenuTreeOperations.findIndexPath(for: targetId, in: items)

        #expect(path == [0, 1, 0])
    }

    @Test("Find index path returns nil for non-existent item")
    func findIndexPathNonExistent() {
        let items = createTestTree()
        let nonExistentId = UUID()

        let path = MenuTreeOperations.findIndexPath(for: nonExistentId, in: items)

        #expect(path == nil)
    }

    // MARK: - Item At Path Tests

    @Test("Get item at root path")
    func itemAtRootPath() {
        let items = createTestTree()

        let item = MenuTreeOperations.item(at: [0], in: items)

        #expect(item?.title == "Item A")
    }

    @Test("Get item at nested path")
    func itemAtNestedPath() {
        let items = createTestTree()

        let item = MenuTreeOperations.item(at: [0, 1], in: items)

        #expect(item?.title == "Sub Item 2")
    }

    @Test("Get item at invalid path returns nil")
    func itemAtInvalidPath() {
        let items = createTestTree()

        let item = MenuTreeOperations.item(at: [10], in: items)

        #expect(item == nil)
    }

    @Test("Get item at empty path returns nil")
    func itemAtEmptyPath() {
        let items = createTestTree()

        let item = MenuTreeOperations.item(at: [], in: items)

        #expect(item == nil)
    }

    // MARK: - Parent Tests

    @Test("Get parent of nested item")
    func parentOfNestedItem() {
        let items = createTestTree()

        let parent = MenuTreeOperations.parent(of: [0, 1], in: items)

        #expect(parent?.title == "Item A")
    }

    @Test("Get parent of root item returns nil")
    func parentOfRootItem() {
        let items = createTestTree()

        let parent = MenuTreeOperations.parent(of: [1], in: items)

        #expect(parent == nil)
    }

    // MARK: - Insert Tests

    @Test("Insert item at root level")
    func insertAtRootLevel() {
        var items = createTestTree()
        let newItem = createTestItem(key: "n", title: "New Item")

        MenuTreeOperations.insert(newItem, at: [1], in: &items)

        #expect(items.count == 4)
        #expect(items[1].title == "New Item")
        #expect(items[2].title == "Item B")
    }

    @Test("Insert item in submenu")
    func insertInSubmenu() {
        var items = createTestTree()
        let newItem = createTestItem(key: "n", title: "New Sub Item")

        MenuTreeOperations.insert(newItem, at: [0, 1], in: &items)

        #expect(items[0].submenu?.count == 3)
        #expect(items[0].submenu?[1].title == "New Sub Item")
    }

    // MARK: - Remove Tests

    @Test("Remove item at root level")
    func removeAtRootLevel() {
        var items = createTestTree()

        let removed = MenuTreeOperations.remove(at: [1], from: &items)

        #expect(removed?.title == "Item B")
        #expect(items.count == 2)
    }

    @Test("Remove nested item")
    func removeNestedItem() {
        var items = createTestTree()

        let removed = MenuTreeOperations.remove(at: [0, 0], from: &items)

        #expect(removed?.title == "Sub Item 1")
        #expect(items[0].submenu?.count == 1)
    }

    @Test("Remove at invalid path returns nil")
    func removeAtInvalidPath() {
        var items = createTestTree()

        let removed = MenuTreeOperations.remove(at: [10], from: &items)

        #expect(removed == nil)
    }

    // MARK: - Update Tests

    @Test("Update item at root level")
    func updateAtRootLevel() {
        var items = createTestTree()
        var updatedItem = items[1]
        updatedItem.title = "Updated Title"

        MenuTreeOperations.update(updatedItem, at: [1], in: &items)

        #expect(items[1].title == "Updated Title")
    }

    @Test("Update nested item")
    func updateNestedItem() {
        var items = createTestTree()
        var updatedItem = items[0].submenu![0]
        updatedItem.title = "Updated Sub Item"

        MenuTreeOperations.update(updatedItem, at: [0, 0], in: &items)

        #expect(items[0].submenu?[0].title == "Updated Sub Item")
    }

    // MARK: - Move Tests

    @Test("Move item within same level")
    func moveWithinSameLevel() {
        var items = createTestTree()
        let originalFirstTitle = items[0].title

        let success = MenuTreeOperations.move(from: [0], to: [2], in: &items)

        #expect(success)
        #expect(items[1].title == originalFirstTitle)
    }

    // MARK: - Flatten Tests

    @Test("Flatten tree returns all items")
    func flattenTree() {
        let items = createTestTree()

        let flattened = MenuTreeOperations.flatten(items)

        #expect(flattened.count == 6) // 3 root + 2 sub + 1 subsub
    }

    @Test("Total count returns correct number")
    func totalCountCorrect() {
        let items = createTestTree()

        let count = MenuTreeOperations.totalCount(items)

        #expect(count == 6)
    }

    // MARK: - Find by ID Tests

    @Test("Find by ID locates item")
    func findByIdLocatesItem() {
        let items = createTestTree()
        let targetId = items[0].submenu![1].id

        let found = MenuTreeOperations.find(id: targetId, in: items)

        #expect(found?.title == "Sub Item 2")
    }

    @Test("Find by ID returns nil for non-existent")
    func findByIdNonExistent() {
        let items = createTestTree()

        let found = MenuTreeOperations.find(id: UUID(), in: items)

        #expect(found == nil)
    }
}
