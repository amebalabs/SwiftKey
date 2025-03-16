#!/bin/bash

# Create placeholder PNG files for all snippets
# This is a temporary solution until proper preview images can be created

# Function to create a colored placeholder image
create_placeholder() {
  local filename=$1
  local text=$2
  
  # Use imagemagick if available, otherwise create empty files
  if command -v convert >/dev/null 2>&1; then
    convert -size 500x300 gradient:#007AFF-#5856D6 \
      -gravity center -pointsize 24 -fill white \
      -annotate 0 "$text" "$filename"
  else
    # Create an empty file as fallback
    touch "$filename"
    echo "Created empty placeholder for $filename (install ImageMagick for better placeholders)"
  fi
}

# Create placeholders for each snippet
create_placeholder "devtools-toolkit.png" "Developer Tools Toolkit"
create_placeholder "quick-apps.png" "Quick App Launcher"
create_placeholder "mac-utils.png" "macOS System Utilities"
create_placeholder "quick-controls.png" "Media Quick Controls"
create_placeholder "web-bookmarks.png" "Web Bookmarks Collection"

# New snippets
create_placeholder "terminal-shortcuts.png" "Terminal Command Shortcuts"
create_placeholder "clipboard-manager.png" "Clipboard Manager"
create_placeholder "screen-capture.png" "Screen Capture Tools"
create_placeholder "file-operations.png" "File Operations Toolkit"
create_placeholder "meeting-tools.png" "Meeting Tools"
create_placeholder "network-tools.png" "Network Diagnostic Tools"
create_placeholder "text-tools.png" "Text Manipulation Tools"
create_placeholder "code-snippets.png" "Code Snippets Library"
create_placeholder "window-management.png" "Window Management"
create_placeholder "search-tools.png" "Search Tools"

echo "Created placeholder preview images"
echo "For production use, replace these with actual screenshots of the menus"