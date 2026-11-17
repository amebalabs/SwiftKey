// The launcha panel in SwiftKey's style: a thin-material card with a search field and a list of
// menu items, micro-apps, apps (or files when nothing else matches) and calculations, with their icons.
import AppKit
import SwiftKeyCore
import SwiftUI

struct LaunchaView: View {
    let model: LaunchaModel
    let chrome: LaunchaChrome
    let onActivate: (_ reveal: Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // A click beside the card closes launcha.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            LaunchaCard(model: model, chrome: chrome, onActivate: onActivate, onDismiss: onDismiss)
                .padding(.top, 8)
        }
    }
}

private struct LaunchaCard: View {
    @Bindable var model: LaunchaModel
    let chrome: LaunchaChrome
    let onActivate: (_ reveal: Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                LaunchaSearchField(text: $model.query, placeholder: "Search menu, apps and files",
                                   focusToken: chrome.focusToken,
                                   onMove: { model.moveSelection(by: $0) },
                                   onSubmit: { onActivate(false) },
                                   onCancel: onDismiss)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !model.rows.isEmpty || model.statusMessage != nil {
                Divider().padding(.horizontal, 8)
            }
            results
            notices
        }
        .padding(.bottom, 8)
        .frame(width: 560)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("launcha")
    }

    @ViewBuilder private var results: some View {
        if model.rows.isEmpty {
            if let message = model.statusMessage {
                Label {
                    Text(message.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    if case .problem = message { Image(systemName: "exclamationmark.triangle") }
                }
                .font(.callout)
                .foregroundStyle(messageStyle(message))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityAddTraits(.updatesFrequently)
            }
        } else {
            ResultList(model: model, chrome: chrome, onActivate: onActivate)
                .padding(.top, 6)
                .padding(.horizontal, 8)
        }
    }

    private func messageStyle(_ message: LaunchaModel.Message) -> AnyShapeStyle {
        if case .problem = message { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

    @ViewBuilder private var notices: some View {
        if let incomplete = model.incompleteMessage {
            notice(incomplete)
        }
        if let problem = model.consentError ?? model.historyIssue {
            notice(problem)
        }
        if model.isExplainingConsent {
            ConsentExplanation(onAllow: {
                model.allowProtectedFolders()
                chrome.focusToken += 1
            }, onCancel: {
                model.isExplainingConsent = false
                chrome.focusToken += 1
            })
            .padding(.horizontal, 12)
            .padding(.top, 8)
        } else if model.showsConsentNotice {
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.caption2)
                Text("Desktop, Documents and Downloads were not searched.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button("Search Them…") { model.isExplainingConsent = true }
                    .buttonStyle(.link)
                    .help("Explains what changes and which macOS prompts may appear")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}

private struct ConsentExplanation: View {
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Desktop, Documents and Downloads?")
                .font(.callout.weight(.semibold))
            Text("launcha will also list apps on your Desktop and find files in these folders. macOS may ask you to allow SwiftKey to access each folder; launcha closes while macOS asks. You can turn this off in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not Now", action: onCancel)
                Button("Allow Access", action: onAllow).buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ResultList: View {
    let model: LaunchaModel
    let chrome: LaunchaChrome
    let onActivate: (_ reveal: Bool) -> Void

    static let rowHeight: CGFloat = 44

    var body: some View {
        let rows = model.rows
        let selection = model.selection
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        ResultRow(row: row, selected: index == selection, chrome: chrome) {
                            model.select(row.id)
                            onActivate(false)
                        }
                        .id(row.id)
                    }
                }
            }
            .scrollIndicators(CGFloat(rows.count) * Self.rowHeight > chrome.maxListHeight ? .automatic : .never)
            .frame(height: min(CGFloat(rows.count) * Self.rowHeight, chrome.maxListHeight))
            .onChange(of: selection) {
                // No animation: also right for Reduce Motion.
                if rows.indices.contains(selection) { proxy.scrollTo(rows[selection].id) }
            }
            .onChange(of: rows.first?.id) {
                if let first = rows.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Results")
    }
}

private struct ResultRow: View {
    let row: LaunchaRow
    let selected: Bool
    let chrome: LaunchaChrome
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(row.isCalculation ? .system(size: 16, weight: .semibold, design: .monospaced)
                                                : .system(size: 14, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.disabled)
                    if !row.detail.isEmpty {
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if let kindLabel {
                    Text(kindLabel)
                        .font(.caption2)
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: ResultList.rowHeight)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder private var icon: some View {
        switch row.kind {
        case .calculation:
            Image(systemName: "equal.square.fill")
                .font(.system(size: 20))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
        case let .menu(_, _, kind, itemID):
            if let itemID, let image = chrome.menuIcon(itemID) {
                image.resizable().scaledToFit().padding(2)
            } else {
                Image(systemName: Self.symbol(for: kind)).font(.system(size: 16))
            }
        case .micro(_, _, let isWorking):
            Image(systemName: isWorking ? "puzzlepiece.extension" : "exclamationmark.triangle")
                .font(.system(size: 16))
        case .app, .file:
            RowIcon(url: row.url, icons: chrome.icons)
        }
    }

    static func symbol(for kind: LaunchaMenuCandidate.Kind) -> String {
        switch kind {
        case .action: "bolt"
        case .group: "folder"
        case .batch: "square.stack.3d.up"
        case .dynamic: "list.bullet.rectangle"
        }
    }

    /// A short word on the right that says what Return does.
    private var kindLabel: String? {
        switch row.kind {
        case .menu(_, _, .group, _), .menu(_, _, .dynamic, _): "Menu"
        case .menu(_, _, .batch, _): "Batch"
        case .menu: "Action"
        case .micro(_, _, true): "Micro-app"
        case .micro: "Errors"
        case .app: "App"
        case .file: nil
        case .calculation: "Copy"
        }
    }

    private var help: String {
        switch row.kind {
        case .menu: row.detail.isEmpty ? row.name : "\(row.detail) › \(row.name)"
        case .micro: row.detail.isEmpty ? row.name : "\(row.name): \(row.detail)"
        case .app, .calculation: row.name
        case .file: row.url.path
        }
    }

    private var accessibilityLabel: String {
        switch row.kind {
        case .menu(_, _, .group, _), .menu(_, _, .dynamic, _): "\(row.name), menu"
        case .menu(_, _, .batch, _): "\(row.name), batch"
        case .menu: row.detail.isEmpty ? "\(row.name), action" : "\(row.name), action in \(row.detail)"
        case .micro(_, _, true): "\(row.name), micro-app"
        case .micro: "\(row.name), micro-app that does not work: \(row.detail)"
        case .app: "\(row.name), app"
        case .file: "\(row.name), file in \(row.detail)"
        case .calculation(let value): "Result \(value)"
        }
    }

    private var accessibilityHint: String {
        switch row.kind {
        case .menu(_, _, .group, _), .menu(_, _, .dynamic, _): "Opens the menu there"
        case .menu(_, _, .batch, _): "Runs every action of the group"
        case .menu: "Runs the action"
        case .micro(_, _, true): "Starts the micro-app"
        case .micro: "Shows the errors of the file"
        case .app: "Opens the app"
        case .file: "Opens the file with its usual app"
        case .calculation: "Copies the result"
        }
    }
}

private struct RowIcon: View {
    let url: URL
    let icons: LaunchaIconCache
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
            }
        }
        .task(id: url) { image = await icons.icon(for: url) }
    }
}
