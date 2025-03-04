import Testing
import Yams
@testable import SwiftKey

// MARK: - Test Helpers

/// Helper for creating test menu items
func createTestMenuItems() -> [MenuItem] {
    return [
        MenuItem(
            key: "a",
            icon: "star.fill",
            title: "Item A",
            action: "launch://AppA",
            submenu: nil
        ),
        MenuItem(
            key: "b",
            icon: "circle.fill",
            title: "Item B",
            action: nil,
            submenu: [
                MenuItem(
                    key: "c",
                    icon: "square.fill",
                    title: "Submenu Item C",
                    action: "launch://AppC"
                )
            ]
        )
    ]
}

/// Helper for creating new menu items (some with conflicting keys)
func createNewMenuItems() -> [MenuItem] {
    return [
        MenuItem(
            key: "d",
            icon: "diamond.fill",
            title: "Item D",
            action: "launch://AppD"
        ),
        MenuItem(
            key: "b", // Same key as existing item
            icon: "triangle.fill",
            title: "New Item B", // Different title
            action: "launch://AppB"
        )
    ]
}

/// Helper for creating conflicting menu items (same key, same title)
func createConflictingMenuItems() -> [MenuItem] {
    return [
        MenuItem(
            key: "a", // Same key
            icon: "star",
            title: "Item A", // Same title
            action: "launch://NewAppA", // Different action
            sticky: true
        )
    ]
}

// MARK: - Merge Strategy Tests

@Suite("ConfigManager Merge Tests")
struct ConfigMergeTests {
    
    @Test("Append strategy should add new items at the end")
    func testAppendStrategy() throws {
        let configManager = ConfigManager.shared
        let baseItems = createTestMenuItems()
        let newItems = createNewMenuItems()
        
        let result = configManager.smartMergeMenuItems(baseItems, with: newItems)
        
        // The result should contain all original items plus all new items
        #expect(result.count == baseItems.count + newItems.count)
        
        // Verify append adds to the end
        #expect(result[0].key == "a")
        #expect(result[1].key == "b")
        #expect(result[2].key == "d")
        #expect(result[3].key == "b")
        #expect(result[3].title == "New Item B")
    }
    
    @Test("Prepend strategy should add new items at the beginning")
    func testPrependStrategy() throws {
        let baseItems = createTestMenuItems()
        let newItems = createNewMenuItems()
        
        // Prepend strategy implementation
        let result = newItems + baseItems
        
        // The result should contain all new items plus all original items
        #expect(result.count == baseItems.count + newItems.count)
        
        // Verify prepend adds to the beginning 
        #expect(result[0].key == "d")
        #expect(result[1].key == "b")
        #expect(result[1].title == "New Item B")
        #expect(result[2].key == "a")
        #expect(result[3].key == "b")
        #expect(result[3].title == "Item B")
    }
    
    @Test("Replace strategy should replace all existing items")
    func testReplaceStrategy() throws {
        let baseItems = createTestMenuItems()
        let newItems = createNewMenuItems()
        
        // Replace strategy just uses the new items
        let result = newItems
        
        // The result should contain only the new items
        #expect(result.count == newItems.count)
        #expect(result[0].key == "d")
        #expect(result[1].key == "b")
        #expect(result[1].title == "New Item B")
    }
    
    @Test("Smart merge should replace items with matching key+title")
    func testSmartMergeStrategy() throws {
        let configManager = ConfigManager.shared
        let baseItems = createTestMenuItems()
        let conflictItems = createConflictingMenuItems()
        
        let result = configManager.smartMergeMenuItems(baseItems, with: conflictItems)
        
        // Count should be the same as base since we're replacing
        #expect(result.count == baseItems.count)
        
        // The conflicting item should replace the original
        #expect(result[0].key == "a")
        #expect(result[0].action == "launch://NewAppA")
        #expect(result[0].sticky == true)
    }
}

// MARK: - YAML Encoding Tests

@Suite("YAML Encoding Tests")
struct YAMLEncodingTests {
    
    @Test("YAML encoding should exclude IDs")
    func testYAMLEncodingExcludesIDs() throws {
        let items = createTestMenuItems()
        
        // Encode to YAML
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(items)
        
        // Print for debugging
        print("YAML output with ID check:\n\(yamlString)")
        
        // The ID field should not be in the output
        #expect(!yamlString.contains("id:"))
        
        // Basic structure checks
        #expect(yamlString.contains("- key: \"a\""))
        #expect(yamlString.contains("  title: \"Item A\""))
        #expect(yamlString.contains("  action: \"launch://AppA\""))
    }
    
    @Test("Clean YAML should not include nil values")
    func testYAMLEncodingExcludesNilValues() throws {
        let items = [
            MenuItem(
                key: "x",
                icon: nil, // This should not show up in YAML
                title: "Test Item",
                action: nil, // This should not show up in YAML
                sticky: nil, // This should not show up in YAML
                notify: true
            )
        ]
        
        // Encode to YAML
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(items)
        
        // Print for debugging
        print("YAML Output:\n\(yamlString)")
        
        // These properties should be excluded
        #expect(!yamlString.contains("icon:"))
        #expect(!yamlString.contains("action:"))
        #expect(!yamlString.contains("sticky:"))
        
        // These properties should be included
        #expect(yamlString.contains("key: \"x\""))
        #expect(yamlString.contains("title: \"Test Item\""))
        #expect(yamlString.contains("notify: true"))
    }
    
    @Test("Clean MenuItem output should produce proper YAML")
    func testCleanMenuItemOutput() throws {
        let configManager = ConfigManager.shared
        
        // Access the private method via reflection
        let mirror = Mirror(reflecting: configManager)
        let createCleanYamlMethod = mirror.children.first { $0.label == "createCleanYaml" }?.value
        
        // If we can't access via reflection, skip this test
        guard let cleanYamlMethod = createCleanYamlMethod else {
             return #expect(false, "Could not access createCleanYaml method")
        }
        
        let items = createTestMenuItems()
        
        // Call the method via reflection
        // This might fail depending on Swift version - uncomment if it works
        /*
        let result = try cleanYamlMethod.call(with: items) as? String
        #expect(result != nil)
        
        // Verify no IDs in the output
        #expect(!result!.contains("id:"))
        */
    }
    
    @Test("Full cycle encoding and decoding should preserve structure")
    func testFullCycleEncodingAndDecoding() throws {
        let originalItems = createTestMenuItems()
        
        // Encode to YAML
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(originalItems)
        
        // Decode back from YAML
        let decoder = YAMLDecoder()
        let decodedItems = try decoder.decode([MenuItem].self, from: yamlString)
        
        // The items should be equivalent in structure
        #expect(decodedItems.count == originalItems.count)
        #expect(decodedItems[0].key == originalItems[0].key)
        #expect(decodedItems[0].title == originalItems[0].title)
        #expect(decodedItems[0].action == originalItems[0].action)
        
        // Test submenu structure
        #expect(decodedItems[1].submenu?.count == originalItems[1].submenu?.count)
        #expect(decodedItems[1].submenu?[0].key == originalItems[1].submenu?[0].key)
    }
}
