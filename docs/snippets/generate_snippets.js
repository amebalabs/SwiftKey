// Script to generate snippet detail pages
const fs = require('fs');
const path = require('path');

// Load snippet data
const snippetsData = JSON.parse(fs.readFileSync('./index.json', 'utf8'));

// Read template
const detailTemplate = fs.readFileSync('./snippet_template.html', 'utf8');

// Create directories if they don't exist
function ensureDir(dirPath) {
    const parts = dirPath.split(path.sep);
    let currentPath = '';
    
    for (const part of parts) {
        currentPath = path.join(currentPath, part);
        if (!fs.existsSync(currentPath)) {
            fs.mkdirSync(currentPath);
        }
    }
}

// Format date for display
function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
    });
}

// Escape HTML special characters
function escapeHtml(text) {
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

// Make sure the previews directory exists
ensureDir('./previews');

// Process each snippet
for (const snippet of snippetsData) {
    console.log(`Processing snippet: ${snippet.name}`);
    
    // Make sure the directory exists
    const snippetDir = path.dirname(snippet.id);
    ensureDir(path.join('.', snippetDir));
    
    // Set a default preview image name in case one isn't specified
    let previewUrl = snippet.previewImageURL;
    if (!previewUrl) {
        previewUrl = `previews/${path.basename(snippet.id)}.png`;
        console.warn(`Warning: No preview image URL specified for "${snippet.name}". Using default: ${previewUrl}`);
    }
    
    // Generate detail page
    let detailHtml = detailTemplate
        .replace(/SNIPPET_NAME/g, snippet.name)
        .replace(/SNIPPET_AUTHOR/g, snippet.author)
        .replace(/SNIPPET_DATE/g, formatDate(snippet.created))
        .replace(/SNIPPET_DESCRIPTION/g, snippet.description)
        .replace(/SNIPPET_PREVIEW_URL/g, previewUrl)
        .replace(/SNIPPET_ID/g, snippet.id)
        .replace(/SNIPPET_CONTENT/g, escapeHtml(snippet.content));
    
    // Generate tags HTML for detail page
    let detailTagsHtml = '';
    for (const tag of snippet.tags) {
        detailTagsHtml += `<div class="snippet-tag">${tag}</div>\n`;
    }
    
    detailHtml = detailHtml.replace(/SNIPPET_TAGS/g, detailTagsHtml);
    
    // Write detail page
    fs.writeFileSync(`./${snippet.id}.html`, detailHtml);
}

// Check if all preview images exist
let missingImages = [];
for (const snippet of snippetsData) {
    const previewUrl = snippet.previewImageURL || `previews/${path.basename(snippet.id)}.png`;
    const imagePath = previewUrl.replace(/^previews\//, './previews/');
    
    if (!fs.existsSync(imagePath)) {
        missingImages.push({
            snippet: snippet.name,
            path: previewUrl
        });
    }
}

console.log("\nGeneration complete!");

if (missingImages.length > 0) {
    console.log("\nWARNING: The following preview images are missing:");
    missingImages.forEach(item => {
        console.log(`- ${item.snippet}: ${item.path}`);
    });
    console.log("\nPlease add these images to the 'previews/' directory.");
}