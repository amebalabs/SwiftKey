import SwiftUI
import AppKit

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Binding var selectedIcon: String?
    @State private var searchText = ""
    @State private var recentIcons = ["star.fill", "folder", "doc", "gear", "bell", "iphone", "mail", "safari", "message"]
    
    // This is a subset of SF Symbols for the demo - in a real app, you'd use a more complete list
    let commonIcons = [
        "folder", "doc", "star", "star.fill", "heart", "heart.fill", "person", "person.fill",
        "gear", "gearshape", "gearshape.fill", "bell", "bell.fill", "link", "globe",
        "safari", "message", "mail", "mail.fill", "phone", "phone.fill", "video", "video.fill",
        "house", "house.fill", "square", "circle", "triangle", "rectangle", "diamond",
        "terminal", "terminal.fill", "printer", "printer.fill", "chevron.right", "chevron.down",
        "arrow.right", "arrow.up", "arrow.down", "arrow.left", "plus", "minus", "xmark",
        "clock", "clock.fill", "calendar", "calendar.badge.plus", "bookmark", "bookmark.fill",
        "tag", "tag.fill", "bolt", "bolt.fill", "magnifyingglass", "trash", "trash.fill",
        "pencil", "square.and.pencil", "checkmark", "checkmark.circle", "checkmark.circle.fill",
        "xmark.circle", "xmark.circle.fill", "exclamationmark.triangle", "questionmark.circle",
        "info.circle", "lock", "lock.fill", "lock.open", "lock.open.fill", "key", "key.fill",
        "lightbulb", "lightbulb.fill", "flag", "flag.fill", "location", "location.fill",
        "gift", "gift.fill", "cart", "cart.fill", "creditcard", "creditcard.fill"
    ]
    
    var filteredIcons: [String] {
        if searchText.isEmpty {
            return commonIcons
        } else {
            return commonIcons.filter { $0.contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            IconSearchBar(searchText: $searchText)
            
            if searchText.isEmpty {
                // Recent icons section
                RecentIconsSection(
                    recentIcons: recentIcons, 
                    selectedIcon: $selectedIcon, 
                    onSelectIcon: updateRecentIcons
                )
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // All icons grid
            IconGrid(
                icons: filteredIcons, 
                selectedIcon: $selectedIcon, 
                onSelectIcon: updateRecentIcons
            )
        }
    }
    
    private func updateRecentIcons(_ icon: String) {
        // Remove if already exists
        recentIcons.removeAll { $0 == icon }
        
        // Add to beginning
        recentIcons.insert(icon, at: 0)
        
        // Limit to 8 recent items
        if recentIcons.count > 8 {
            recentIcons = Array(recentIcons.prefix(8))
        }
    }
}

// MARK: - Icon Search Bar

struct IconSearchBar: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search icons", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(8)
        .background(Color(NSColor.systemGray))
    }
}

// MARK: - Recent Icons Section

struct RecentIconsSection: View {
    let recentIcons: [String]
    @Binding var selectedIcon: String?
    var onSelectIcon: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Recent")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                ForEach(recentIcons, id: \.self) { icon in
                    IconButton(icon: icon, isSelected: selectedIcon == icon) {
                        selectedIcon = icon
                        onSelectIcon(icon)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Icon Grid

struct IconGrid: View {
    let icons: [String]
    @Binding var selectedIcon: String?
    var onSelectIcon: (String) -> Void
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    IconButton(icon: icon, isSelected: selectedIcon == icon) {
                        selectedIcon = icon
                        onSelectIcon(icon)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                
                if isSelected {
                    Text(icon)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - Preview

struct IconPickerView_Previews: PreviewProvider {
    @State static var selectedIcon: String? = "star.fill"
    
    static var previews: some View {
        IconPickerView(selectedIcon: $selectedIcon)
            .frame(width: 300, height: 400)
    }
}