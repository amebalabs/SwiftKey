# SwiftKey Snippets System

This directory contains the code and assets for the SwiftKey Snippets gallery, a community-driven repository of configuration snippets for SwiftKey.

## Directory Structure

- `index.html` - Main snippets gallery page
- `index.json` - JSON data file containing all snippets
- `snippet_template.html` - Template for individual snippet detail pages
- `snippets.js` - JavaScript for the gallery functionality
- `snippets.css` - CSS styles for the gallery
- `generate_snippets.js` - Node.js script to generate detail pages
- `previews/` - Directory containing preview images for snippets
- Various subdirectories for snippets organized by category (e.g., `developer/`, `web/`, etc.)

## How to Add a New Snippet

### 1. Prepare Your Files

- Create your YAML snippet content
- Create a preview image (PNG format, 500×300px recommended)
- Choose an appropriate category and ID for your snippet

### 2. Submit a Pull Request

Add your snippet to `index.json` following the existing format:

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

Add your preview image to the `previews/` directory:
- Name it according to your snippet ID (e.g., `snippet-id.png`)
- Use PNG format with a size of approximately 500×300px
- Ensure the image clearly showcases your snippet's functionality

### 3. Generate Detail Pages

After your PR is approved, a maintainer will run:

```bash
node generate_snippets.js
```

This will create the individual detail pages for your snippet automatically.

## Preview Image Guidelines

- **Size**: 500×300px recommended
- **Format**: PNG with transparent background if possible
- **Content**: Include your snippet name, a brief description, and a visual representation of the menu structure
- **Style**: Use colors that match the SwiftKey theme (blue gradient recommended)

## Development

To update the gallery:

1. Edit the templates, CSS, or JavaScript as needed
2. Run the generation script to update all pages
3. Test locally by opening `index.html` in a browser