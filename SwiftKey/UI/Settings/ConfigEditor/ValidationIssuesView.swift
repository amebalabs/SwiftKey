import SwiftUI

struct ValidationIssuesView: View {
    let validationErrors: [UUID: [ConfigEditorViewModel.ValidationError]]
    let menuItems: [MenuItem]
    
    private var allIssues: [(item: MenuItem, errors: [ConfigEditorViewModel.ValidationError])] {
        var issues: [(item: MenuItem, errors: [ConfigEditorViewModel.ValidationError])] = []
        
        func findItem(with id: UUID, in items: [MenuItem]) -> MenuItem? {
            for item in items {
                if item.id == id {
                    return item
                }
                if let submenu = item.submenu,
                   let found = findItem(with: id, in: submenu) {
                    return found
                }
            }
            return nil
        }
        
        for (itemId, errors) in validationErrors {
            if let item = findItem(with: itemId, in: menuItems), !errors.isEmpty {
                issues.append((item: item, errors: errors))
            }
        }
        
        return issues.sorted { first, second in
            first.item.title < second.item.title
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Validation Issues")
                    .font(.headline)
                Spacer()
                Text("\(allIssues.count) item\(allIssues.count == 1 ? "" : "s") with issues")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Issues list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(allIssues, id: \.item.id) { item, errors in
                        VStack(alignment: .leading, spacing: 6) {
                            // Item header
                            HStack {
                                if let icon = item.icon {
                                    Image(systemName: icon)
                                        .foregroundColor(.secondary)
                                }
                                Text(item.title.isEmpty ? "Untitled" : item.title)
                                    .font(.system(.body, weight: .medium))
                                Text("[\(item.key.isEmpty ? "no key" : item.key)]")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            // Errors for this item
                            ForEach(errors) { error in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: iconForSeverity(error.severity))
                                        .foregroundColor(colorForSeverity(error.severity))
                                        .font(.caption)
                                        .frame(width: 16)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(error.message)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Text("Field: \(error.field)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func iconForSeverity(_ severity: ConfigEditorViewModel.ValidationError.Severity) -> String {
        switch severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    private func colorForSeverity(_ severity: ConfigEditorViewModel.ValidationError.Severity) -> Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}