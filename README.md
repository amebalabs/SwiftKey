[![GitHub license](https://img.shields.io/github/license/amebalabs/SwiftKey.svg)](https://github.com/amebalabs/SwiftKey/blob/master/LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/amebalabs/SwiftKey)](https://github.com/amebalabs/SwiftKey/releases/latest)

<p align="center">
    <a href="https://swiftkey.app"><img width="128" height="128" src="docs/logo.png" style="filter: drop-shadow(0px 2px 4px rgba(80, 50, 6, 0.2));"></a>
    <h1 align="center"><code style="text-shadow: 0px 3px 10px rgba(8, 0, 6, 0.35); font-size: 3rem; font-family: ui-monospace, Menlo, monospace; font-weight: 800; background: transparent; color: #4d3e56; padding: 0.2rem 0.2rem; border-radius: 6px">SwiftKey</code></h1>
    <h4 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace;">Hackable Launcher</h4>
    <h6 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace; font-weight: 400;">Right at your fingertips</h6>
</p>

## Overview

SwiftKey is a powerful macOS productivity tool that provides quick access to applications, shortcuts, and custom actions through customizable keyboard shortcuts and an elegant overlay interface.

**TL;DR:** A highly customizable keyboard-driven launcher for macOS with multiple interface styles and YAML configuration.

## Features
- 🎯 Multiple overlay styles:
  - Panel mode with horizontal/vertical layouts
  - HUD mode for a compact interface
  - Menu bar mode for minimal interference
- ⌨️ Fully keyboard-driven interface
- 🔧 YAML-based configuration
- 🔄 Dynamic menu generation
- 🚀 Support for various action types:
  - Launch applications
  - Open URLs
  - Run shell commands
  - Execute Apple Shortcuts
- 🎨 SF Symbols integration for menu icons
- 🔍 Deep linking support
- 📦 Automatic updates with beta channel support

## Installation
1. Download the latest release from the Releases page
2. Move SwiftKey.app to your Applications folder
3. Launch SwiftKey and follow the onboarding process

## Configuration
SwiftKey uses YAML for configuration. Here's a basic example:

```yaml
- key: "c"
  title: "Launch Notes"
  action: "launch:///System/Applications/Notes.app"

- key: "b"
  icon: "bookmark.fill"
  title: "Bookmarks"
  batch: true
  submenu:
    - key: "t"
      title: "TechCrunch"
      action: "open://https://techcrunch.com"
    - key: "v"
      title: "The Verge"
      action: "open://https://www.theverge.com"
    - key: "w"
      title: "Wired"
      action: "open://https://www.wired.com"
    - key: "a"
      title: "Ars Technica"
      action: "open://https://arstechnica.com"
    - key: "e"
      title: "Engadget"
      action: "open://https://www.engadget.com"
```

## Action Types
- `launch://` — Launch applications
- `open://` — Open URLs
- `shell://` — Execute shell commands
- `shortcut://` — Run Apple Shortcuts
- `dynamic://` — Generate dynamic menus

## Menu Item Properties
- `key` — Single character trigger key
- `icon` — SF Symbol name or omit for automatic icons
- `title` — Display title
- `action` — Action to execute
- `stick` — Keep overlay open after execution (optional)
- `notify` — Show notification after execution (optional)
- `batch` — Execute all submenu items (optional). Alternative: hold ⌥ for batch execution.
- `submenu` — Nested menu items (optional)
- `hotkey` — Global keyboard shortcut (optional)

## Global Hotkeys
SwiftKey allows you to assign global hotkeys to any menu item. Hotkeys work even when the overlay is not visible:

```yaml
# Direct action hotkey
- key: "c"
  title: "Launch Calculator"
  action: "launch:///Applications/Calculator.app"
  hotkey: "cmd+ctrl+c"

# Submenu navigation hotkey
- key: "d"
  title: "Development"
  hotkey: "cmd+shift+d"  # Opens this submenu
  submenu:
    - key: "1"
      title: "VS Code"
      action: "launch:///Applications/Visual Studio Code.app"
    - key: "2"
      title: "Terminal"
      action: "launch:///System/Applications/Terminal.app"

# Nested submenu with hotkey
- key: "u"
  title: "Utilities"
  submenu:
    - key: "s"
      title: "System Tools"
      hotkey: "alt+cmd+s"  # Direct access to this submenu
      submenu:
        - key: "1"
          title: "Activity Monitor"
          action: "launch:///System/Applications/Activity Monitor.app"
```

Supported hotkey formats:
- Modifiers: `cmd`, `ctrl`, `alt`, `shift`
- Keys: letters, numbers, function keys (f1-f12), arrows, and special keys
- Examples:
  - `cmd+shift+a`
  - `ctrl+alt+p`
  - `cmd+f12`
  - `shift+space`

Hotkeys can:
1. Execute actions directly — work globally without showing the overlay
2. Open specific submenus

## Deep Linking
SwiftKey supports deep linking through the swiftkey:// URL scheme:
```swiftkey://open?path=a,b,c```

This opens the menu and navigates through the specified path.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
