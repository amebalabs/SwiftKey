# Contributing to SwiftKey Snippets

Thank you for your interest in contributing to SwiftKey Snippets! This guide will walk you through the process of adding a new snippet to our collection.

## Contribution Process

1. **Fork the Repository**: Start by forking the SwiftKey repository.

2. **Create Your Snippet**: Prepare your snippet files following the guidelines below.

3. **Submit a Pull Request**: Submit your changes as a pull request with a clear description of your new snippet.

## Snippet Requirements

Each snippet consists of two key components:

### 1. JSON Entry

Add your snippet to `docs/snippets/index.json` following this format:

```json
{
  "id": "category/snippet-id",
  "name": "Snippet Name",
  "description": "Description of the snippet",
  "author": "Your Name",
  "tags": ["tag1", "tag2", "tag3"],
  "created": "YYYY-MM-DD",
  "content": "# YAML content goes here\n- key: \"x\"\n  ...",
  "previewImageURL": "previews/snippet-id.png"
}
```

Notes:
- `id`: Use a category prefix (e.g., "developer/", "system/", "productivity/")
- `tags`: Include 2-5 relevant tags
- `content`: The YAML menu configuration formatted as a string with `\n` for line breaks
- `previewImageURL`: Path to your preview image

### 2. Preview Image

Create a preview image for your snippet:

- **Format**: PNG with transparent background if possible
- **Size**: 500×300px recommended
- **Filename**: Should match your snippet ID (e.g., `snippet-id.png`)
- **Location**: Add to the `docs/snippets/previews/` directory

The preview image should visually represent your snippet, including its name, a brief description, and a representation of the menu structure.

## Content Guidelines

### YAML Content

- Follow SwiftKey's YAML format for menu definitions
- Include clear, descriptive menu titles
- Use appropriate SF Symbol names for icons
- Ensure all actions are properly formatted

### Descriptions

- Keep descriptions concise (under 200 characters)
- Clearly explain what your snippet does
- Mention any special requirements or dependencies

### Tags

- Use lowercase tags
- Include relevant categories and use cases
- Reuse existing tags where appropriate

## Testing Your Snippet

Before submitting, you should:

1. Validate your YAML with a YAML linter
2. Test your snippet in the SwiftKey app
3. Ensure your preview image displays correctly

## Pull Request Process

1. Create a branch with a descriptive name (e.g., `add-developer-tools-snippet`)
2. Add your snippet JSON entry and preview image
3. Submit a pull request with a clear title and description
4. Respond to any feedback from maintainers

The maintainers will review your submission and may suggest changes. Once approved, your snippet will be added to the collection!

## Need Help?

If you have any questions about contributing, please:

- Open an issue in the GitHub repository
- Reach out to the maintainers
- Check existing snippets for examples

Thank you for helping to grow the SwiftKey snippets collection!