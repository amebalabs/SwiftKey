import Foundation
import Yams

class DynamicMenuLoader {
    static let shared = DynamicMenuLoader()

    /**
     Loads a dynamic menu for a MenuItem with a dynamic:// action

     - Parameters:
       - menuItem: The menu item containing a dynamic:// action
       - completion: Closure called with the parsed menu items or nil if an error occurred

     - Note: This function executes the shell command asynchronously and calls the completion handler on a background thread.
     */
    func loadDynamicMenu(
        for menuItem: MenuItem,
        completion: @escaping ([MenuItem]?) -> Void
    ) {
        guard let actionString = menuItem.action, actionString.hasPrefix("dynamic://") else {
            completion(nil)
            return
        }

        let command = String(actionString.dropFirst("dynamic://".count))

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try runScript(to: command, args: [])
                let output = result.out
                let decoder = YAMLDecoder()
                let menuItems = try decoder.decode([MenuItem].self, from: output)
                completion(menuItems)
            } catch {
                print("Dynamic menu error: \(error)")
                completion(nil)
            }
        }
    }
}
