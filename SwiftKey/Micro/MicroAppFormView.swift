// The parameter panel in SwiftKey's style: one field per parameter, in file order, with the
// prompt as label. Required fields are always visible; optional ones sit behind ⌘O and an icon.
// Tab moves between the visible fields, ↩ runs from any field (taken by the flow panel), Esc closes.
import AppKit
import SwiftUI
import SwiftKeyCore

/// The form of one start: the pure `MicroAppForm` plus focus, typed filters and the mark of the
/// field that stopped Enter.
@MainActor
@Observable
final class MicroAppFormModel {
    let app: MicroApp
    var form: MicroAppForm
    /// The index of the field with keyboard focus.
    private(set) var focus: Int
    /// Bumped when the focus must move into `focus` (and select its text).
    private(set) var focusToken = 0
    /// The field that stopped ↩ (an empty required text, or a choice filter with no match), and why.
    private(set) var mark: (index: Int, block: MicroAppForm.Block)?
    var missing: Int? { mark?.index }
    /// The letters typed in a choice field, by field index.
    private(set) var queries: [Int: String] = [:]

    init(app: MicroApp, form: MicroAppForm) {
        self.app = app
        self.form = form
        focus = form.visibleIndexes.first ?? 0
    }

    func filtered(_ index: Int) -> [String] {
        MicroAppChoiceFilter.options(form.fields[index].choices ?? [], matching: queries[index] ?? "")
    }

    func query(_ index: Int) -> String { queries[index] ?? "" }

    func setText(_ text: String, at index: Int) {
        guard form.fields.indices.contains(index) else { return }
        if form.fields[index].choices != nil {
            queries[index] = text
            if let marked = MicroAppChoiceFilter.mark(form.fields[index].value, in: filtered(index)) {
                form.fields[index].value = marked
                if missing == index { mark = nil }
            }
        } else {
            form.fields[index].value = text
            if missing == index { mark = nil }
        }
    }

    func move(_ step: Int, at index: Int) {
        guard form.fields.indices.contains(index), form.fields[index].choices != nil,
              let next = MicroAppChoiceFilter.move(form.fields[index].value, by: step, in: filtered(index)) else { return }
        form.fields[index].value = next
    }

    func choose(_ option: String, at index: Int) {
        guard form.fields.indices.contains(index) else { return }
        form.fields[index].value = option
        queries[index] = nil
        if missing == index { mark = nil }
        focus(index)
    }

    /// The field was focused by a click.
    func didFocus(_ index: Int) {
        guard focus != index else { return }
        focus = index
    }

    /// A field lost focus: a choice field forgets its letters and shows its marked option again.
    func didLeave(_ index: Int) {
        queries[index] = nil
        if mark?.index == index, mark?.block == .noOption { mark = nil }
    }

    func focus(_ index: Int) {
        focus = index
        focusToken += 1
    }

    func focusNext(_ step: Int) {
        if let next = form.nextVisible(after: focus, by: step) { focus(next) }
    }

    /// ⌘O and the icon: shows or hides the optional fields. Opening moves the focus to the first
    /// optional field; closing moves it back when it was in a hidden one.
    func toggleOptional() {
        guard form.hasOptionalToggle else { return }
        form.optionalOpen.toggle()
        if form.optionalOpen, let first = form.fields.indices.first(where: { form.fields[$0].isOptional }) {
            focus(first)
        } else if !form.visibleIndexes.contains(focus) {
            focus(form.visibleIndexes.first ?? 0)
        }
    }

    /// ↩: the shown values, or `nil` after marking and focusing the first field that stops it: an
    /// empty required text, or a choice field whose letters match no option (its old value is hidden,
    /// so it never runs unseen).
    func submit() -> [String: String]? {
        if let blocked = form.firstBlocked(queries: queries) {
            mark = blocked
            focus(blocked.index)
            return nil
        }
        return form.values
    }
}

/// The fields in file order. Taller than `maxHeight`, the form scrolls, and the focused or marked
/// field is scrolled into view.
struct MicroAppFormBody: View {
    let model: MicroAppFormModel
    /// The highest form height inside the flow panel (`MicroAppFormLayout.maxFormHeight`).
    let maxHeight: CGFloat
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                fields
                    .padding(.vertical, 2)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: FormHeightKey.self, value: geometry.size.height)
                    })
            }
            .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : min(maxHeight, 120))
            .onPreferenceChange(FormHeightKey.self) { contentHeight = $0 }
            .onChange(of: model.focusToken) { proxy.scrollTo(model.focus) }
            .onChange(of: model.focus) { proxy.scrollTo(model.focus) }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.app.description.isEmpty {
                Text(model.app.description).font(.system(size: 12)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // File order: an optional field stays between the required fields around it.
            ForEach(model.form.visibleIndexes, id: \.self) {
                FieldRow(model: model, index: $0).id($0)
            }
            if model.form.hasOptionalToggle {
                OptionalToggle(model: model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OptionalToggle: View {
    let model: MicroAppFormModel

    var body: some View {
        let count = model.form.fields.filter(\.isOptional).count
        Button(action: model.toggleOptional) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                Text(model.form.optionalOpen ? "Hide options" : "Options (\(count))").font(.system(size: 12))
                Image(systemName: model.form.optionalOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                Text("⌘O").font(.caption).foregroundStyle(Color.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.form.optionalOpen ? "Hide the optional parameters (⌘O)" : "Show the optional parameters (⌘O)")
        .accessibilityLabel(model.form.optionalOpen ? "Hide optional parameters" : "Show \(count) optional parameters")
    }
}

private struct FieldRow: View {
    let model: MicroAppFormModel
    let index: Int

    var body: some View {
        let field = model.form.fields[index]
        let focused = model.focus == index
        let missing = model.missing == index
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(field.param.shownPrompt).font(.caption)
                    .foregroundStyle(focused ? Color.accentColor : Color.secondary)
                if missing {
                    Text(model.mark?.block == .noOption ? "No option matches; choose one" : "Required")
                        .font(.system(size: 11)).foregroundStyle(Color.red)
                }
                Spacer()
            }
            .accessibilityHidden(true)
            FormTextField(model: model, index: index, focused: focused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(missing ? Color.red : (focused ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor).opacity(0.7)),
                                  lineWidth: missing || focused ? 1.25 : 0.75))
            if field.choices != nil, focused || model.form.isSingleChoiceList {
                ChoiceList(model: model, index: index)
            }
        }
    }
}

private struct ChoiceList: View {
    let model: MicroAppFormModel
    let index: Int

    static let rowHeight: CGFloat = 28

    var body: some View {
        let options = model.filtered(index)
        let value = model.form.fields[index].value
        if options.isEmpty {
            Text("No option matches").font(.system(size: 12)).foregroundStyle(Color.secondary).padding(.leading, 10)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(options, id: \.self) { option in
                            let marked = option == value
                            Button { model.choose(option, at: index) } label: {
                                HStack {
                                    Text(option).font(.system(size: 13, weight: marked ? .medium : .regular))
                                    Spacer()
                                    if marked {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accentColor).accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: Self.rowHeight)
                                .background(RoundedRectangle(cornerRadius: 6).fill(marked ? Color.accentColor.opacity(0.18) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(marked ? .isSelected : [])
                            .id(option)
                        }
                    }
                }
                .scrollIndicators(options.count > 8 ? .automatic : .never)
                .frame(height: min(CGFloat(options.count), 8) * Self.rowHeight)
                .onChange(of: value) { proxy.scrollTo(value) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.form.fields[index].param.shownPrompt)
        }
    }
}

/// A plain NSTextField, so typing, paste, any keyboard layout and input methods work. A text field
/// edits its value; a choice field takes letters that filter its options and shows the marked option
/// while nothing is typed. Tab, ⇧Tab and the arrows of a choice field are taken from it.
private struct FormTextField: NSViewRepresentable {
    let model: MicroAppFormModel
    let index: Int
    let focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusReportingField {
        let field = FocusReportingField()
        field.onFocus = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.model.didFocus(coordinator.parent.index)
        }
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FocusReportingField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let item = model.form.fields[index]
        let isChoice = item.choices != nil
        let text = isChoice ? model.query(index) : item.value
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !composing, field.stringValue != text { field.stringValue = text }
        let placeholder = isChoice ? item.value : ""
        let color: NSColor = isChoice ? .labelColor : .placeholderTextColor
        if field.placeholderAttributedString?.string != placeholder {
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: color, .font: NSFont.systemFont(ofSize: 14),
            ])
        }
        field.setAccessibilityLabel(item.param.shownPrompt)
        field.setAccessibilityValueDescription(isChoice ? item.value : nil)
        field.setAccessibilityHelp(isChoice
            ? "Up and down arrows choose an option; letters filter. Return runs. Tab moves to the next field."
            : "Return runs. Tab moves to the next field. Escape closes.")
        if focused, coordinator.focusToken != model.focusToken {
            coordinator.focusToken = model.focusToken
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.selectAll(nil)
            }
        } else if !focused {
            coordinator.focusToken = model.focusToken
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FormTextField
        var focusToken: Int?

        init(_ parent: FormTextField) { self.parent = parent }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.model.didLeave(parent.index)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            parent.model.didFocus(parent.index)
            parent.model.setText(field.stringValue, at: parent.index)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let model = parent.model
            let index = parent.index
            switch selector {
            case #selector(NSResponder.insertTab(_:)): model.focusNext(1)
            case #selector(NSResponder.insertBacktab(_:)): model.focusNext(-1)
            case #selector(NSResponder.moveUp(_:)) where model.form.fields[index].choices != nil: model.move(-1, at: index)
            case #selector(NSResponder.moveDown(_:)) where model.form.fields[index].choices != nil: model.move(1, at: index)
            default: return false
            }
            return true
        }
    }
}

/// Reports when it takes keyboard focus, also by a click, so Tab goes on from the right field.
final class FocusReportingField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}
