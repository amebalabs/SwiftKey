import SwiftUI
import AppKit

// MARK: - Menu Config Toolbar

struct MenuConfigToolbar: View {
    @Binding var searchText: String
    var onExpandAll: () -> Void
    var onCollapseAll: () -> Void
    var onSave: () -> Void
    
    var body: some View {
        HStack {
            // Search box
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search menu items", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(7)
            .background(Color(NSColor.systemGray))
            .cornerRadius(8)
            
            Spacer()
            
            // Action buttons
            Button(action: onExpandAll) {
                Label("Expand All", systemImage: "chevron.down.square")
            }
            .buttonStyle(.borderless)
            
            Button(action: onCollapseAll) {
                Label("Collapse All", systemImage: "chevron.right.square")
            }
            .buttonStyle(.borderless)
            
            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding([.horizontal, .top])
    }
}

// MARK: - Preview

struct MenuConfigToolbar_Previews: PreviewProvider {
    @State static var searchText = ""
    
    static var previews: some View {
        MenuConfigToolbar(
            searchText: $searchText,
            onExpandAll: {},
            onCollapseAll: {},
            onSave: {}
        )
        .frame(width: 600)
        .previewLayout(.sizeThatFits)
    }
}