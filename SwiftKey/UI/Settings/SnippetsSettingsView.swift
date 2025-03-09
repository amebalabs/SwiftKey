import SwiftUI

struct SnippetsSettingsView: View {  
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Snippets Gallery")
                .font(.headline)

            Text("Browse and install shared configuration snippets from the SwiftKey community.")
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(nil)

            Button("Open Snippets Gallery") {
                NotificationCenter.default
                    .post(name: .presentGalleryWindow, object: nil)
            }
            .controlSize(.large)

            Divider()

            Text("Share Your Snippets")
                .font(.headline)

            Text(
                "Got a useful configuration? Share it with the community by submitting a pull request to the snippets repository."
            )
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(nil)

            Link(
                "Learn How to Share Snippets",
                destination: URL(string: "https://github.com/amebalabs/swiftkey-snippets")!
            )
            .padding(.top, 5)

            Spacer()
        }
        .frame(width: 420, height: 250)
        .padding()
    }
}

#Preview {
    SnippetsSettingsView()
}
