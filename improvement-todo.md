# SwiftKey Improvement Plan

## High Priority Improvements

1. ✅ Create ConfigManager class to handle YAML config loading/parsing
   - Created dedicated ConfigManager class with reactive updates using Combine
   - Improved error handling for configuration loading
   - Added efficient change detection without polling
   - Used publishers to propagate configuration changes

2. ✅ Implement dependency injection for singletons
   - Created DependencyContainer class to manage dependencies
   - Updated AppDelegate, ConfigManager, and MenuState to use dependency injection
   - Implemented DependencyInjectable protocol
   - Fixed issue with static subscription handling

3. ✅ Add error handling for YAML parsing
   - Added detailed error messages with line/column information
   - Implemented validation for required fields and types
   - Added UI for displaying errors in the settings
   - Enhanced error extraction from YAML parser
   - Fixed first-launch config loading issues

4. ✅ Optimize menu item rendering
   - Implemented image caching for SF Symbols and app icons
   - Added caching for NSImage objects to reduce disk I/O
   - Created dedicated MenuItemIconView with Equatable support
   - Added identity tracking for menu items to reduce redraws
   - Improved SwiftUI rendering with better component structure

5. ✅ Consolidate keyboard handling
   - Created centralized KeyboardManager class for all keyboard interactions
   - Removed duplicate code across different UI components
   - Unified hotkey handling for global shortcuts
   - Improved structure with dependency injection
   - Implemented robust hotkey registration through both observer pattern and notifications
   - Added full lifecycle management for keyboard shortcuts with proper cleanup

6. Improve test coverage
   - Add unit tests for ConfigManager YAML parsing and validation
   - Create tests for KeyboardManager and keyboard handling logic
   - Add tests for SnippetsStore functionality

7. ✅ Refactor RunScript.swift 
   - Removed "horrible hack" code and improved implementation
   - Implemented proper error handling with ScriptError enum and logging
   - Fixed commented out code and simplified Data extension
   - Added clear separation between streaming/non-streaming paths

8. ✅ Standardize error handling
   - Replaced inconsistent patterns with Result pattern in ConfigManager
   - Fixed invalid assertions (`assert(true)`) with proper assertions
   - Implemented proper error logging with os.Logger across the entire codebase

9. ✅ Modernize asynchronous code
   - Migrated from GCD/callbacks to async/await where appropriate
   - Simplified error handling with structured concurrency
   - Ensured proper main thread handling for UI updates
   - Completed migration from KeyPressController to KeyboardManager

10. Enhance thread safety
    - Audit all UI update code to ensure proper main thread execution
    - Add explicit thread synchronization for shared resources
    - Document threading expectations for key components

11. Consolidate literals and constants
    - Create centralized enum or constants file for AppStorage keys
    - Remove "magic strings" throughout the codebase
    - Standardize naming conventions for constants

## Medium Priority Improvements

12. ✅ Implement icon caching

13. Add accessibility improvements
    - Implement VoiceOver support
    - Add keyboard navigation for all UI components
    - Ensure proper contrast ratios and text sizing

14. Create unit tests for core functionality

15. ✅ Add validation for shell commands
    - Implemented comprehensive shell command validation in ConfigManager
    - Added blacklist for potentially dangerous commands
    - Enhanced error reporting with specific messages for shell command issues
    - Added runtime validation for commands before execution
    - Improved error handling and notifications for shell command execution

16. Optimize app startup performance
    - Reduce initialization time for key components
    - Implement lazy loading where appropriate
    - Profile and address startup bottlenecks

17. Fix performance bottlenecks
    - Optimize ConfigManager loading with multiple attempts
    - Reduce excessive validation steps before parsing configuration
    - Improve SnippetsStore performance with proper caching

18. Improve documentation
    - Add comprehensive documentation comments to public APIs
    - Create architectural diagrams for complex subsystems
    - Document design decisions and component relationships

## Low Priority Improvements

19. Support CloudKit for settings sync

20. Enhance deep linking capabilities

21. Improve multi-display support
    - Fix positioning issues on multiple monitors
    - Ensure proper scaling and layout on different displays

22. Add settings backup/restore
    - Create export/import functionality for user settings
    - Implement version migration for settings

23. Implement staged rollouts for updates

24. ✅ Remove stale debug code
    - Removed excessive print statements across the codebase
    - Created centralized AppLogger for consistent logging
    - Implemented proper os.Logger with categories and privacy flags
    - Added appropriate log levels (debug, info, notice, error, fault)

25. Modernize Carbon API usage for keyboard handling
    - Abstract low-level Carbon hotkey registration APIs
    - Explore more modern alternatives if available
    - Improve reliability of keyboard input source handling
