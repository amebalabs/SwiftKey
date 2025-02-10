#!/bin/bash

# Install SwiftFormat if not installed
if ! command -v swiftformat &> /dev/null; then
    echo "SwiftFormat not found. Installing via Homebrew..."
    brew install swiftformat
fi

# Create symbolic link for the pre-commit hook
ln -sf ../../swiftformat.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "SwiftFormat pre-commit hook installed successfully!"
