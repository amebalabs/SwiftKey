import Combine
import SwiftUI

struct SnippetsGalleryView: View {
    @ObservedObject var viewModel: SnippetsGalleryViewModel
    @State private var searchText = ""
    @State private var isDetailPresented = false
    @State private var selectedSnippet: ConfigSnippet?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var mergeStrategy: MergeStrategy = .smart

    init(viewModel: SnippetsGalleryViewModel = SnippetsGalleryViewModel()) {
        self.viewModel = viewModel
    }

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 20),
    ]

    var body: some View {
        VStack {
            searchBar

            if viewModel.isLoading {
                loadingView
            } else if viewModel.snippets.isEmpty {
                emptyStateView
            } else {
                snippetsGrid
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .padding()
        .onAppear {
            viewModel.fetchSnippets()
        }
        .sheet(isPresented: $isDetailPresented) {
            if let snippet = selectedSnippet {
                SnippetDetailView(snippet: snippet, mergeStrategy: $mergeStrategy) { strategy in
                    importSnippet(snippet, strategy: strategy)
                }
                .frame(width: 700, height: 600) // Increase size to prevent clipping
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search snippets...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: searchText) { _, _ in
                    viewModel.search(query: searchText)
                }

            Button(action: {
                viewModel.fetchSnippets()
            }) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Refresh snippets")
        }
        .padding(.bottom)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("Loading snippets...")
                .font(.headline)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ? "No snippets available" : "No snippets match your search")
                .font(.headline)

            Button("Refresh") {
                viewModel.fetchSnippets()
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snippetsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(viewModel.filteredSnippets) { snippet in
                    SnippetCard(snippet: snippet)
                        .onTapGesture {
                            selectedSnippet = snippet
                            isDetailPresented = true
                        }
                }
                .id(UUID()) // Force refresh when snippets change
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Helper Functions

    private func importSnippet(_ snippet: ConfigSnippet, strategy: MergeStrategy) {
        viewModel.importSnippet(snippet, strategy: strategy) { result in
            switch result {
            case .success:
                // Successfully imported
                isDetailPresented = false
            case let .failure(error):
                // Handle error
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
}

// MARK: - Snippet Card

struct SnippetCard: View {
    let snippet: ConfigSnippet

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snippet.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Text(snippet.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            HStack {
                Text("by \(snippet.author)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                ForEach(snippet.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .frame(height: 140)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Snippet Detail View

struct SnippetDetailView: View {
    let snippet: ConfigSnippet
    @Binding var mergeStrategy: MergeStrategy
    let onImport: (MergeStrategy) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(snippet.name)
                        .font(.largeTitle)
                        .bold()
                        .lineLimit(1) // Limit to one line
                        .truncationMode(.tail) // Add ellipsis if needed

                    Spacer()

                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.leading, 10)
                }
                .padding(.trailing, 10)

                Text(snippet.description)
                    .font(.title3)

                HStack {
                    Text("Author: \(snippet.author)")
                        .font(.subheadline)

                    Spacer()

                    if let updated = snippet.updateDate {
                        Text("Updated: \(dateFormatter.string(from: updated))")
                            .font(.caption)
                    } else if let created = snippet.creationDate {
                        Text("Created: \(dateFormatter.string(from: created))")
                            .font(.caption)
                    } else {
                        Text("Created: \(snippet.created)")
                            .font(.caption)
                    }
                }

                HStack {
                    Text("Tags:")
                        .font(.subheadline)

                    ForEach(snippet.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Divider()

                Text("Preview:")
                    .font(.headline)

                if let menuItems = snippet.menuItems {
                    List {
                        MenuItemPreviewRow(menuItems: menuItems, level: 0)
                    }
                    .frame(height: 200) // Increase height for better visibility
                    .border(Color.secondary.opacity(0.3), width: 1)
                } else {
                    Text("Could not parse snippet content")
                        .foregroundColor(.red)
                }

                Divider()

                VStack(alignment: .leading) {
                    Text("Merge Strategy:")
                        .font(.headline)

                    Picker("", selection: $mergeStrategy) {
                        Text("Smart Merge").tag(MergeStrategy.smart)
                        Text("Append").tag(MergeStrategy.append)
                        Text("Prepend").tag(MergeStrategy.prepend)
                        Text("Replace").tag(MergeStrategy.replace)
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text(mergeStrategyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                }

                Spacer(minLength: 20)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .padding()
                    .controlSize(.large)

                    Button("Import") {
                        onImport(mergeStrategy)
                    }
                    .padding()
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.large)
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var mergeStrategyDescription: String {
        switch mergeStrategy {
        case .smart:
            return "Intelligently merge with your current configuration, avoiding key conflicts"
        case .append:
            return "Add the snippet at the end of your current configuration"
        case .prepend:
            return "Add the snippet at the beginning of your current configuration"
        case .replace:
            return "Replace your entire configuration with this snippet"
        }
    }
}

// MARK: - Menu Item Preview

struct MenuItemPreviewRow: View {
    let menuItems: [MenuItem]
    let level: Int

    @State private var isExpanded = true

    var body: some View {
        ForEach(menuItems) { item in
            VStack(alignment: .leading) {
                HStack {
                    ForEach(0 ..< level, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                    }

                    if let submenu = item.submenu, !submenu.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .onTapGesture {
                                isExpanded.toggle()
                            }
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                    }

                    if let icon = item.icon {
                        Image(systemName: icon)
                    }

                    Text("[\(item.key)] \(item.title)")
                        .lineLimit(1)

                    Spacer()

                    if let action = item.action {
                        Text(action)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if isExpanded, let submenu = item.submenu, !submenu.isEmpty {
                    MenuItemPreviewRow(menuItems: submenu, level: level + 1)
                }
            }
        }
    }
}

// MARK: - View Model

class SnippetsGalleryViewModel: ObservableObject {
    @Published var snippets: [ConfigSnippet] = []
    @Published var isLoading = false
    @Published var selectedSnippet: ConfigSnippet?
    @Published var isDetailPresented = false

    var filteredSnippets: [ConfigSnippet] {
        return snippetsStore.filteredSnippets
    }

    private let snippetsStore: SnippetsStore
    private let preselectedSnippetId: String?

    init(snippetsStore: SnippetsStore? = nil, preselectedSnippetId: String? = nil) {
        // Use provided store or get from dependency container
        self.snippetsStore = snippetsStore ?? DependencyContainer.shared.snippetsStore
        self.preselectedSnippetId = preselectedSnippetId
    }

    func fetchSnippets() {
        isLoading = true
        snippetsStore.fetchSnippets()

        // Update our local snippets directly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.snippets = self.snippetsStore.snippets
            self.isLoading = false

            // Check for preselected snippet if needed
            if let preselectedId = self.preselectedSnippetId,
               !self.snippets.isEmpty
            {
                if let snippet = self.snippets.first(where: { $0.id == preselectedId }) {
                    self.selectedSnippet = snippet
                    self.isDetailPresented = true
                }
            }
        }
    }

    func search(query: String) {
        snippetsStore.searchSnippets(query: query)
        objectWillChange.send()
    }

    func importSnippet(
        _ snippet: ConfigSnippet,
        strategy: MergeStrategy,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let result = snippetsStore.importSnippet(snippet, mergeStrategy: strategy)
        completion(result)
    }
}
