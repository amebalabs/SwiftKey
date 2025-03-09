import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack {
            HStack {
                Image("mac_512")
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 90, height: 90, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("SwiftKey")
                        .font(.title3)
                        .bold()
                    Text(
                        "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"
                    )
                    .font(.subheadline)
                    Text(
                        "Copyright ©\(NumberFormatter.localizedString(from: NSNumber(value: Calendar.current.component(.year, from: Date())), number: .none)) Ameba Labs. All rights reserved."
                    )
                    .font(.footnote)
                    .padding(.top, 10)
                }
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Visit our Website", action: {
                    NSWorkspace.shared.open(URL(string: "https://ameba.co")!)
                })
                Button("Contact Us", action: {
                    NSWorkspace.shared.open(URL(string: "mailto:info@ameba.co")!)
                })
            }.padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(width: 420, height: 140)
    }
}

#Preview {
    AboutSettingsView()
}
