# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |


## Reporting a Vulnerability

None

## How SwiftKey runs code

Some menu items run code: `shell://` commands, `dynamic://` menus and micro-apps.
SwiftKey runs such code only after you approve its exact text.

- The first time a command runs, or after it changes in any way, SwiftKey shows a
  window with the command, the menu path of its item and where it came from: an
  imported snippet, an imported file, or an edit of the config file outside
  SwiftKey's editor. Return and Esc cancel; approving takes a click or ⌘↩.
- Approvals are stored as SHA-256 hashes in
  `~/Library/Application Support/SwiftKey/approvals.json`, apart from the config
  file. A copied config, a snippet or another program that edits the config never
  approves anything. A missing or unreadable approvals file approves nothing.
- A command you type in SwiftKey's configuration editor is approved when you save
  the configuration, because you wrote it there.
- One approval covers all the commands of a batch item.
- Items that an approved `dynamic://` command prints run without another approval:
  the command that printed them could run the same code itself.
- `launch://`, `open://` and `shortcut://` items run without approval. Apple
  Shortcuts asks for its own permissions.

## Deep links

Any web page or app can open a `swiftkey://` link. A link of the form
`swiftkey://open?path=a,b` runs a `launch://`, `open://` or `shortcut://` item at
once. For a `shell://`, `dynamic://` or micro-app item it only opens the menu at the
item's group and names the key to press: code never runs from a link alone.
