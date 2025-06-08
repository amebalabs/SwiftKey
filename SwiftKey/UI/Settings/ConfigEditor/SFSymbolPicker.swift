import SwiftUI

struct SFSymbolPicker: View {
    let selectedSymbol: String
    let onSelect: (String) -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: SymbolCategory = .all
    @Environment(\.dismiss) private var dismiss
    
    enum SymbolCategory: String, CaseIterable {
        case all = "All"
        case communication = "Communication"
        case devices = "Devices"
        case nature = "Nature"
        case objects = "Objects"
        case people = "People"
        case symbols = "Symbols"
        case transportation = "Transportation"
        
        var symbols: [String] {
            switch self {
            case .all:
                return SymbolCategory.allSymbols
            case .communication:
                return ["envelope", "envelope.fill", "envelope.circle", "envelope.circle.fill",
                       "phone", "phone.fill", "phone.circle", "phone.circle.fill",
                       "message", "message.fill", "bubble.left", "bubble.right",
                       "video", "video.fill", "video.circle", "video.circle.fill",
                       "mic", "mic.fill", "mic.circle", "mic.circle.fill"]
            case .devices:
                return ["desktopcomputer", "laptopcomputer", "iphone", "ipad",
                       "applewatch", "airpods", "airpodspro", "homepod",
                       "tv", "tv.fill", "display", "display.2",
                       "keyboard", "keyboard.fill", "computermouse", "computermouse.fill"]
            case .nature:
                return ["sun.max", "sun.max.fill", "moon", "moon.fill",
                       "cloud", "cloud.fill", "cloud.rain", "cloud.rain.fill",
                       "bolt", "bolt.fill", "snow", "wind",
                       "leaf", "leaf.fill", "flame", "flame.fill"]
            case .objects:
                return ["folder", "folder.fill", "folder.circle", "folder.circle.fill",
                       "doc", "doc.fill", "doc.text", "doc.text.fill",
                       "book", "book.fill", "bookmark", "bookmark.fill",
                       "paperclip", "paperclip.circle", "link", "link.circle"]
            case .people:
                return ["person", "person.fill", "person.circle", "person.circle.fill",
                       "person.2", "person.2.fill", "person.3", "person.3.fill",
                       "figure.stand", "figure.walk", "figure.wave", "figure.run"]
            case .symbols:
                return ["star", "star.fill", "star.circle", "star.circle.fill",
                       "heart", "heart.fill", "heart.circle", "heart.circle.fill",
                       "plus", "plus.circle", "plus.circle.fill", "minus",
                       "checkmark", "checkmark.circle", "checkmark.circle.fill", "xmark"]
            case .transportation:
                return ["car", "car.fill", "car.circle", "car.circle.fill",
                       "airplane", "tram", "tram.fill", "bicycle"]
            }
        }
        
        static var allSymbols: [String] {
            var symbols: [String] = []
            for category in SymbolCategory.allCases where category != .all {
                symbols.append(contentsOf: category.symbols)
            }
            return Array(Set(symbols)).sorted()
        }
    }
    
    private var recentSymbols: [String] {
        // TODO: Load from UserDefaults
        ["star.fill", "folder.fill", "doc.text.fill", "checkmark.circle.fill", "gear"]
    }
    
    private var filteredSymbols: [String] {
        let symbols = selectedCategory.symbols
        
        if searchText.isEmpty {
            return symbols
        } else {
            return symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Choose Symbol")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search symbols", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Category picker
                Picker("", selection: $selectedCategory) {
                    ForEach(SymbolCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
            }
            .padding()
            
            Divider()
            
            // Symbol grid
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Recently used section
                    if searchText.isEmpty && selectedCategory == .all {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently Used")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(60)), count: 8), spacing: 12) {
                                ForEach(recentSymbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                        
                        Divider()
                    }
                    
                    // All symbols
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(60)), count: 8), spacing: 12) {
                        ForEach(filteredSymbols, id: \.self) { symbol in
                            symbolButton(symbol)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer with preview
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Image(systemName: selectedSymbol)
                            .font(.system(size: 32))
                        
                        VStack(alignment: .leading) {
                            Text(selectedSymbol)
                                .font(.headline)
                            Text("Current selection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button("Select") {
                    onSelect(selectedSymbol)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedSymbol.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
    
    @ViewBuilder
    private func symbolButton(_ symbol: String) -> some View {
        Button(action: { onSelect(symbol) }) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .frame(width: 40, height: 40)
                    .foregroundColor(symbol == selectedSymbol ? .white : .primary)
                
                Text(symbol)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(symbol == selectedSymbol ? .white : .secondary)
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(symbol == selectedSymbol ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(symbol == selectedSymbol ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(symbol)
    }
}