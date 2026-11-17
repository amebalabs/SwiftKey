import Foundation
import Combine
@testable import SwiftKey

final class MockConfigManager: ConfigManaging {

    // MARK: - Properties

    var menuItems: [MenuItem] = []
    var configError: ConfigError?
    var validationIssues: [ValidationIssue] = []
    var configFileURL: URL?

    private let menuItemsSubject = CurrentValueSubject<[MenuItem], Never>([])

    var menuItemsPublisher: AnyPublisher<[MenuItem], Never> {
        menuItemsSubject.eraseToAnyPublisher()
    }

    // MARK: - Test Control

    var loadConfigurationResult: Result<[MenuItem], ConfigError> = .success([])
    var validationIssuesToReturn: [ValidationIssue] = []
    var shouldThrowOnSave = false
    var saveError: Error?

    // MARK: - Call Tracking

    private(set) var loadConfigurationCallCount = 0
    private(set) var reloadConfigurationCallCount = 0
    private(set) var validateMenuItemsCallCount = 0
    private(set) var saveConfigurationCallCount = 0
    private(set) var lastSavedItems: [MenuItem]?
    private(set) var lastValidatedItems: [MenuItem]?

    // MARK: - ConfigManaging Implementation

    func loadConfiguration() async -> Result<[MenuItem], ConfigError> {
        loadConfigurationCallCount += 1

        switch loadConfigurationResult {
        case .success(let items):
            menuItems = items
            menuItemsSubject.send(items)
            configError = nil
            return .success(items)
        case .failure(let error):
            configError = error
            return .failure(error)
        }
    }

    func reloadConfiguration() async {
        reloadConfigurationCallCount += 1
        _ = await loadConfiguration()
    }

    func validateMenuItems(_ items: [MenuItem]) -> [ValidationIssue] {
        validateMenuItemsCallCount += 1
        lastValidatedItems = items
        return validationIssuesToReturn
    }

    func saveConfiguration(_ items: [MenuItem]) async throws {
        saveConfigurationCallCount += 1
        lastSavedItems = items

        if shouldThrowOnSave {
            throw saveError ?? ConfigError.saveFailed(underlying: NSError(domain: "Test", code: 1))
        }

        menuItems = items
        menuItemsSubject.send(items)
    }

    // MARK: - Test Helpers

    func reset() {
        menuItems = []
        configError = nil
        validationIssues = []
        loadConfigurationResult = .success([])
        validationIssuesToReturn = []
        shouldThrowOnSave = false
        saveError = nil
        loadConfigurationCallCount = 0
        reloadConfigurationCallCount = 0
        validateMenuItemsCallCount = 0
        saveConfigurationCallCount = 0
        lastSavedItems = nil
        lastValidatedItems = nil
    }

    func simulateMenuItemsChange(_ items: [MenuItem]) {
        menuItems = items
        menuItemsSubject.send(items)
    }
}
