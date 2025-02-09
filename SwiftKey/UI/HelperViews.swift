import SwiftUI

struct ToggleView: View {
    let label: String
    let secondLabel: String
    @Binding var state: Bool
    let width: CGFloat
    
    var mainLabel: String {
        guard !label.isEmpty else { return "" }
        return "\(label):"
    }
    
    var body: some View {
        HStack {
            HStack {
                Spacer()
                Text(mainLabel)
            }.frame(width: width)
            Toggle("", isOn: $state)
            Text(secondLabel)
            Spacer()
        }
    }
}
