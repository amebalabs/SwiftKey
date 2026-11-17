# Configuring SwiftKey with a coding agent

This document tells a coding agent such as Claude Code, Codex or pi how to
change SwiftKey for a person: menu items and micro-apps. It ships inside the app
as `SwiftKey.app/Contents/Resources/CONFIGURING.md`; the micro-app format is in
`FORMAT.md` next to it.

The person asks in plain words, for example:

> Write a new micro-app: the main key, then `t` `a`, should translate the clipboard into German.

> Add `w` `j` to open https://jira.example.com.

> Open Ghostty with the main key, then `space`.

## Files

| What | Where |
|---|---|
| Menu items | the config file, by default `~/Documents/menu.yaml` |
| Micro-apps | `micro/*.yaml` next to the config file |
| Libraries of micro-apps | `micro/libs/*.yaml` next to the config file |
| Problems of micro-app files | `micro-errors.log` next to the config file |
| Console tool | `/Applications/SwiftKey.app/Contents/MacOS/swiftkey-micro` |
| Micro-app format | `/Applications/SwiftKey.app/Contents/Resources/FORMAT.md` |

The person can choose another config file in SwiftKey Settings › Config Editor,
which shows the file in use. With `SWIFTKEY_CONFIG=/path/x.yaml` set, the config
is that file, the micro-apps are in `/path/x.yaml.micro/` and the log is
`/path/x.yaml.micro-errors.log`.

SwiftKey reloads the config file and the micro-apps folder by itself when they
change; nothing needs a restart. **Never** write the approvals, history and
remembered values in `~/Library/Application Support/SwiftKey/`, and never change
`SwiftKey.app`.

## The config file

The config is a YAML list of menu items:

```yaml
- key: "space"
  title: "Ghostty"
  action: "launch://com.mitchellh.ghostty"

- key: "t"
  title: "Translate"
  icon: "character.bubble"
  submenu:
    - key: "u"
      title: "Translate to Ukrainian"
      action: "micro://translate-ukrainian"

- key: "w"
  title: "Web"
  submenu:
    - key: "g"
      title: "GitHub"
      action: "open://https://github.com"
```

- The list is a tree. The sequence main key, `t`, `u` is the item with
  `key: "u"` inside the item with `key: "t"`.
- Each item has `key` and `title`, and either `action` or `submenu`.
- `key`: one printable character (`a` and `A` are different keys; `A` is typed
  with Shift), or one of `space`, `return`, `f1`…`f20`. Keys are Latin even when
  the person types with another layout. In one submenu a key is used once.
- `action`:
  - `launch://` and an app path or a bundle identifier
    (`launch://com.apple.Safari`); a running app comes to the front.
  - `open://` and a URL, including schemes such as `raycast://`.
  - `shell://` and a shell command.
  - `shortcut://` and the name of an Apple Shortcut.
  - `dynamic://` and a command that prints a menu (a YAML list of items).
  - `micro://` and a micro-app id.
- Optional keys: `icon` (an SF Symbol name), `sticky` (the menu stays open),
  `notify` (a notification after the action), `batch` (choosing the submenu runs
  all its actions), `hidden` (not shown, still reachable by its key) and
  `hotkey` (a global hotkey such as `cmd+shift+h` or `f13`; never a modifier
  alone).

Find an app's bundle identifier with
`mdls -name kMDItemCFBundleIdentifier -r /Applications/Ghostty.app`.

`shell://`, `dynamic://` and `micro://` items run only after the person approves
their exact text at the first start, and again after each change. A
`swiftkey://open?path=…` link to such an item only opens the menu at it; the
person still presses its key.

## Changing the config

1. Read the config file and find where the change goes. Keep every other item
   and the order of the file.
2. Ask the person first when the change would replace or move something:
   - the sequence is already used;
   - a shorter part of it is an action, not a submenu. For example, `t` opens
     Terminal, and you need `t` `a`.
3. Copy the file to a backup in a temporary folder, then edit it. Keep it valid
   YAML in the shape above.
4. SwiftKey shows problems in Settings › Config Editor: duplicate keys, invalid
   keys, hotkeys and actions, and `micro://` ids that do not load.
5. Tell the person what changed and the backup path.

## Adding a micro-app with a key

1. Read `FORMAT.md` and follow its workflow: look for a library to reuse, write
   and check the file in a temporary folder, then move it into the `micro/`
   folder next to the config.
2. Add an item with `action: "micro://<id>"` at the sequence the person asked
   for, creating the submenus on the way.
3. Tell the person that the first start shows an approval window and that
   `⌘↩` approves the file. Name any API key or keychain item the micro-app
   needs.

### Worked example

> Write a new micro-app: the main key, then `t` `a`, should translate the clipboard into German.

1. `~/Documents/micro/libs/translate.yaml` exists and its step has
   `id: translate`. Inherit it instead of copying the prompt. Write
   `translate-german.yaml` in a temporary folder:

   ```yaml
   format: ting.microapp/2
   inherit: translate
   id: translate-german
   name: Translate to German
   description: Translate the clipboard text into German with OpenAI.

   steps:
     - id: translate
       params:
         language: German
   ```

   Without that library, write the micro-app with its own `ai` step, or first
   move the shared steps into a new library if other translate micro-apps
   exist.
2. Check the file against the person's libraries:

   ```sh
   MICRO=/Applications/SwiftKey.app/Contents/MacOS/swiftkey-micro
   "$MICRO" check --libs ~/Documents/micro/libs "$dir/translate-german.yaml"
   ```

   Then move it into `~/Documents/micro/` and read `~/Documents/micro-errors.log`.
3. In the config file, the item `t` exists (`title: "Translate"`) with a
   `submenu`. Key `a` is free there, so add to that submenu:

   ```yaml
   - key: "a"
     title: "Translate to German"
     action: "micro://translate-german"
   ```

   Without an item `t`, add one with `title: "Translate"` and a `submenu`. If
   `t` is used for something else, ask first.
4. Report: "Main key, t, a runs Translate to German. Approve it with ⌘↩ at the
   first start. It uses OPENAI_API_KEY from your shell."

Do not run the micro-app yourself to test it when it calls a paid API or changes
files; ask first. `swiftkey-micro run` runs it without the panels and the
clipboard.

## A prompt for the person

The person can start an agent with this text and add the task at the end:

```text
Change my SwiftKey setup. Read /Applications/SwiftKey.app/Contents/Resources/CONFIGURING.md
and follow it; for micro-apps it points to FORMAT.md. Check every micro-app with
swiftkey-micro before you finish. Never put API keys into files and never touch
~/Library/Application Support/SwiftKey/.

My task:
```

**Copy Prompt for Agent** in SwiftKey Settings › General copies a ready text
with the paths of this Mac.
