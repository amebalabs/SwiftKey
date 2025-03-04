document.addEventListener('DOMContentLoaded', () => {
    fetchSnippets();
});

let allSnippets = [];
let activeTags = [];

// Fetch snippets from index.json
async function fetchSnippets() {
    try {
        const response = await fetch('index.json');
        if (!response.ok) {
            throw new Error('Failed to fetch snippets');
        }
        
        allSnippets = await response.json();
        
        // Generate and display tag filters
        generateTagFilters();
        
        // Display snippets
        displaySnippets(allSnippets);
    } catch (error) {
        console.error('Error fetching snippets:', error);
        document.getElementById('snippet-grid').innerHTML = `
            <div class="error-message">
                <i class="fas fa-exclamation-circle"></i>
                <p>Failed to load snippets. Please try again later.</p>
            </div>
        `;
    }
}

// Generate tag filters from snippets
function generateTagFilters() {
    const tagFilterContainer = document.getElementById('tag-filters');
    const allTags = new Set();
    
    // Collect all unique tags
    allSnippets.forEach(snippet => {
        snippet.tags.forEach(tag => allTags.add(tag));
    });
    
    // Sort tags alphabetically
    const sortedTags = Array.from(allTags).sort();
    
    // Add "All" tag
    const allTagElement = document.createElement('div');
    allTagElement.className = 'tag active';
    allTagElement.textContent = 'All';
    allTagElement.dataset.tag = 'all';
    allTagElement.addEventListener('click', () => toggleTag('all'));
    tagFilterContainer.appendChild(allTagElement);
    
    // Add each unique tag
    sortedTags.forEach(tag => {
        const tagElement = document.createElement('div');
        tagElement.className = 'tag';
        tagElement.textContent = tag;
        tagElement.dataset.tag = tag;
        tagElement.addEventListener('click', () => toggleTag(tag));
        tagFilterContainer.appendChild(tagElement);
    });
}

// Toggle tag selection
function toggleTag(tag) {
    const searchInput = document.getElementById('snippet-search');
    const tagElement = document.querySelector(`.tag[data-tag="${tag}"]`);
    
    if (tag === 'all') {
        // Clear all active tags
        activeTags = [];
        document.querySelectorAll('.tag').forEach(el => {
            el.classList.remove('active');
        });
        tagElement.classList.add('active');
    } else {
        // Remove "All" tag
        document.querySelector('.tag[data-tag="all"]').classList.remove('active');
        
        // Toggle current tag
        if (tagElement.classList.contains('active')) {
            tagElement.classList.remove('active');
            activeTags = activeTags.filter(t => t !== tag);
            
            // If no tags are active, activate "All" tag
            if (activeTags.length === 0) {
                document.querySelector('.tag[data-tag="all"]').classList.add('active');
            }
        } else {
            tagElement.classList.add('active');
            activeTags.push(tag);
        }
    }
    
    // Filter snippets based on tags and search query
    filterSnippets(searchInput.value);
}

// Filter snippets based on search query and selected tags
function filterSnippets() {
    const searchInput = document.getElementById('snippet-search');
    const query = searchInput.value.toLowerCase();
    
    let filteredSnippets = allSnippets;
    
    // Apply search filter
    if (query) {
        filteredSnippets = filteredSnippets.filter(snippet => 
            snippet.name.toLowerCase().includes(query) || 
            snippet.description.toLowerCase().includes(query) ||
            snippet.author.toLowerCase().includes(query) ||
            snippet.tags.some(tag => tag.toLowerCase().includes(query))
        );
    }
    
    // Apply tag filter if any tags are selected
    if (activeTags.length > 0) {
        filteredSnippets = filteredSnippets.filter(snippet => 
            activeTags.some(tag => snippet.tags.includes(tag))
        );
    }
    
    displaySnippets(filteredSnippets);
}

// Display snippets in the grid
function displaySnippets(snippets) {
    const grid = document.getElementById('snippet-grid');
    
    if (snippets.length === 0) {
        grid.innerHTML = `
            <div class="no-results">
                <i class="fas fa-search"></i>
                <p>No snippets found matching your criteria.</p>
            </div>
        `;
        return;
    }
    
    grid.innerHTML = '';
    
    snippets.forEach(snippet => {
        const date = new Date(snippet.created);
        const formattedDate = date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
        
        const card = document.createElement('div');
        card.className = 'snippet-card';
        card.innerHTML = `
            <div class="snippet-header">
                <h3 class="snippet-title">${snippet.name}</h3>
                <div class="snippet-author">By ${snippet.author}</div>
                <div class="snippet-date">${formattedDate}</div>
            </div>
            <div class="snippet-description">
                ${snippet.description}
            </div>
            <div class="snippet-footer">
                <div class="snippet-tags">
                    ${snippet.tags.slice(0, 3).map(tag => `
                        <div class="snippet-tag">${tag}</div>
                    `).join('')}
                    ${snippet.tags.length > 3 ? `<div class="snippet-tag">+${snippet.tags.length - 3}</div>` : ''}
                </div>
                <div class="snippet-actions">
                    <a href="${snippet.id}.html" title="View Details">
                        <i class="fas fa-eye"></i>
                    </a>
                    <a href="swiftkey://snippets/${snippet.id}" title="Open in SwiftKey App">
                        <i class="fas fa-download"></i>
                    </a>
                </div>
            </div>
        `;
        
        grid.appendChild(card);
    });
}

// Mobile menu toggle
document.querySelector('.mobile-menu-btn').addEventListener('click', function() {
    document.querySelector('.mobile-menu').classList.toggle('active');
    this.classList.toggle('active');
});

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        e.preventDefault();
        
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth'
            });
        }
        
        // Close mobile menu if open
        document.querySelector('.mobile-menu').classList.remove('active');
        document.querySelector('.mobile-menu-btn').classList.remove('active');
    });
});