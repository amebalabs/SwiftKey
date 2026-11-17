import SwiftKeyRuntime
// One micro-app start: approval (through `ApprovalGate`) → context → parameter panel → working
// state → result (panel, clipboard, the app or a mix).
// Only one flow is open at a time; a new start closes the open one and stops its command.
import AppKit
import SwiftKeyCore
import SwiftUI

/// The flow window: a non-activating panel that takes keyboard focus, like launcha.
/// ↩, ⌘↩, ⌘O and Esc go to the flow; other keys go to the panel's views (the fields, the result text).
final class MicroAppFlowPanel: NSPanel {
    enum Key { case enter, commandEnter, escape, toggleOptional }
    var onKey: ((Key) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // While an input method composes in a field, ↩ and Esc belong to it.
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch event.keyCode {
            case 53:
                onKey?(.escape)
                return
            case 36, 76:
                if flags.isEmpty { onKey?(.enter); return }
                if flags == .command { onKey?(.commandEnter); return }
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    /// SwiftKey has no Edit menu while it is not the active app: ⌘C, ⌘X, ⌘V, ⌘A and ⌘Z go to the
    /// text here, and ⌘O shows the optional parameters, matched by the Latin layout. ⌘Return and
    /// ⌘Enter confirm. Every other ⌘ shortcut is swallowed, so ⌘Q never quits SwiftKey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command else { return flags.contains(.command) ? true : super.performKeyEquivalent(with: event) }
        // AppKit sends Command shortcuts here before `sendEvent`, so Cmd+Enter is handled here.
        if event.keyCode == 36 || event.keyCode == 76 {
            onKey?(.commandEnter)
            return true
        }
        switch KeyTranslator.latin(event.keyCode, shift: false) {
        case "c": NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "x": NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "v": NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a": NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "z": firstResponder?.undoManager?.undo()
        case "o": onKey?(.toggleOptional)
        default: break
        }
        return true
    }
}

/// What the flow panel shows now.
@MainActor
@Observable
final class MicroAppFlowSession {
    enum State: Equatable {
        case closed
        case form(MicroApp)
        case working(MicroApp)
        case result(MicroAppPanelContent)
    }

    var state: State = .closed {
        didSet {
            if case .form = state {} else { form = nil }
            if case .working = state {} else { progress = nil }
        }
    }
    /// The running step and the live output of the last step; set only while `state` is `.working`.
    var progress: MicroAppRunProgress?
    /// The open parameter panel; set only while `state` is `.form`.
    var form: MicroAppFormModel?
    /// The highest parameter form height in the current panel; beyond it the form scrolls.
    var formMaxHeight = CGFloat(MicroAppFormLayout.maxFormHeight(panelHeight: MicroAppFormLayout.panelCap))
}

@MainActor
final class MicroAppFlowController: NSObject, NSWindowDelegate, MicroAppRunning {
    let session = MicroAppFlowSession()
    /// Shows a short message (the 'Copied' note, errors that fit two lines).
    var onToast: ((String) -> Void)?
    /// A micro-app needs Accessibility and SwiftKey does not have it.
    var onAccessibilityNeeded: (() -> Void)?
    /// The micro-apps folder as the user sees it, for the 'not found' error and the approval.
    var folderDisplay: () -> String = { "the micro-apps folder" }

    private(set) var catalog = MicroAppCatalog()
    /// Approves each micro-app before it runs.
    let gate: ApprovalGate
    private let values: MicroAppValueStore
    private let runner: MicroAppRunner
    /// The clipboard: stdin of `input: clipboard` and the `clipboard` target.
    private let pasteboard: NSPasteboard
    /// Reads the `context` of a micro-app.
    private let contextReader: MicroAppContextReading
    /// Sends `keys`, `paste` and the `app` output to the app where the micro-app started.
    private let keyboard: MicroAppKeyboardSending
    /// The app in front, read at each start.
    private let frontmost: @MainActor () -> MicroAppTarget?
    /// The app that was in front when the open flow started.
    private var target: MicroAppTarget?
    /// The context of the open flow, read before its parameter panel.
    private var context = MicroAppContext()
    /// The generation of the run that asked for Accessibility: its failure shows no panel.
    private var accessibilityAsked: Int?
    /// `false` builds the panel with its real views and key handling but never puts it on screen
    /// or gives it keyboard focus. For tests, so the user's screen and typing are not touched.
    private let presentsWindow: Bool
    private var panel: MicroAppFlowPanel?
    private var task: Task<Void, Never>?
    /// Bumped by every start and close, so a late result of a stopped flow is dropped.
    private var generation = 0
    /// The approval window of a start is open.
    private var isAuthorizing = false
    /// How the open flow went so far; handed to `finish` when the flow ends.
    private var outcome = MicroAppOutcome.notRun
    /// Resumed once when the open flow ends.
    private var finish: CheckedContinuation<MicroAppOutcome, Never>?

    init(gate: ApprovalGate, values: MicroAppValueStore? = nil, runner: MicroAppRunner = MicroAppRunner(),
         pasteboard: NSPasteboard = .general, presentsWindow: Bool = true, contextReader: MicroAppContextReading? = nil,
         keyboard: MicroAppKeyboardSending? = nil, frontmost: (@MainActor () -> MicroAppTarget?)? = nil) {
        self.gate = gate
        self.values = values ?? MicroAppValueStore()
        self.runner = runner
        self.pasteboard = pasteboard
        self.presentsWindow = presentsWindow
        let real = MicroAppKeyboard(pasteboard: pasteboard)
        self.keyboard = keyboard ?? real
        self.contextReader = contextReader ?? MicroAppContextReader(copySelection: { await real.copySelection(from: $0) })
        self.frontmost = frontmost ?? { MicroAppTarget.frontmost() }
    }

    var isOpen: Bool { session.state != .closed }
    /// The flow panel, once a step has shown it.
    var flowPanel: MicroAppFlowPanel? { panel }

    func setCatalog(_ catalog: MicroAppCatalog) {
        self.catalog = catalog
    }

    // MARK: Starts

    /// Starts the micro-app bound as `id` and returns when its flow has ended. A missing or broken
    /// micro-app shows its error and starts nothing.
    func run(id: String, path: [String] = []) async -> MicroAppOutcome {
        await start(path: path, title: id) { catalog in
            let resolution = catalog.resolve(id)
            guard case .working(let app, let entry) = resolution else {
                return .failure(MicroAppStartProblem(message: resolution.problem(id: id, folder: self.folderDisplay())
                    ?? "Micro-app `\(id)` cannot start"))
            }
            return .success((app, entry))
        }
    }

    /// Starts the file `file` of the folder, as launcha starts a broken file: shows that file's
    /// own errors, or goes through the normal start when the file works by now.
    func run(file: String) async -> MicroAppOutcome {
        await start(path: [], title: file) { catalog in
            switch catalog.resolve(file: file) {
            case .working(let app, let entry):
                return .success((app, entry))
            case .broken(let entry):
                return .failure(MicroAppStartProblem(message: MicroAppResolution.broken(entry).problem(id: entry.bindingID,
                                                                                                        folder: self.folderDisplay())
                    ?? "Micro-app \(file) has errors"))
            case .missing:
                return .failure(MicroAppStartProblem(message: "Micro-app file `\(file)` not found in \(self.folderDisplay())"))
            }
        }
    }

    private func start(path: [String], title: String,
                       resolve: (MicroAppCatalog) -> Result<(MicroApp, MicroAppEntry), MicroAppStartProblem>) async -> MicroAppOutcome {
        // One approval at a time: a start while the approval window is open does not end the flow
        // waiting for it, or approving it would run nothing.
        guard !isAuthorizing else { return .notRun }
        close()
        target = frontmost()
        let started = generation
        switch resolve(catalog) {
        case .failure(let problem):
            present(MicroAppResultPlan.error(title: title, message: problem.message))
        case .success(let (app, entry)):
            let file = (folderDisplay() as NSString).appendingPathComponent(entry.file)
            isAuthorizing = true
            let approved = await gate.authorizeMicroApp(app, hash: entry.contentHash, file: file, path: path)
            isAuthorizing = false
            guard approved, generation == started else { return .notRun }
            prepare(app)
        }
        guard isOpen || task != nil else { return outcome }
        return await withCheckedContinuation { continuation in
            finish = continuation
        }
    }

    /// Closes any panel and stops a running command, silently. The clipboard stays as it was.
    func close() {
        generation += 1
        task?.cancel()
        task = nil
        session.state = .closed
        let wasShown = panel?.isVisible == true
        panel?.orderOut(nil)
        // After an approval SwiftKey is the active app: give the keyboard back to the app the
        // person worked in.
        if wasShown, NSApp.isActive, let pid = target?.pid, pid != ProcessInfo.processInfo.processIdentifier {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        let ended = outcome
        outcome = .notRun
        if let finish {
            self.finish = nil
            finish.resume(returning: ended)
        }
    }

    // MARK: Steps

    /// Reads the context the micro-app lists, then asks its parameters.
    private func prepare(_ app: MicroApp) {
        context = MicroAppContext()
        let sources = app.requiredContext
        guard !sources.isEmpty else { return askParameters(app) }
        generation += 1
        let current = generation
        let reader = contextReader
        let target = self.target
        task = Task { [weak self] in
            let result: Result<MicroAppContext, Error>
            do { result = .success(try await reader.read(sources, target: target)) } catch { result = .failure(error) }
            guard let self, self.generation == current, !Task.isCancelled else { return }
            self.task = nil
            switch result {
            case .success(let context):
                self.context = context
                self.askParameters(app)
            case .failure(let error) where error.needsAccessibility:
                self.close()
                self.onAccessibilityNeeded?()
            case .failure(let error):
                self.present(MicroAppResultPlan.error(title: app.shownName, message: error.localizedDescription))
            }
        }
    }

    /// The parameter panel, the same for every start way. A micro-app without parameters runs at once.
    private func askParameters(_ app: MicroApp) {
        values.load()
        let form = MicroAppForm.start(app, remembered: values.remembered)
        guard !form.isEmpty else { return run(app, values: [:]) }
        session.form = MicroAppFormModel(app: app, form: form)
        show(.form(app))
    }

    /// ↩ in the parameter panel: runs with the shown values and remembers them, or marks the empty
    /// required field and runs nothing.
    private func submitForm() {
        guard let model = session.form, case .form = session.state, let shown = model.submit() else { return }
        do {
            try values.remember(shown, for: model.app)
        } catch {
            onToast?("Cannot save the values: \(error.localizedDescription)")
        }
        run(model.app, values: shown)
    }

    private func run(_ app: MicroApp, values: [String: String]) {
        generation += 1
        let current = generation
        show(.working(app))
        let stdin = app.input == .clipboard ? (pasteboard.string(forType: .string) ?? "") : nil
        var runner = self.runner
        let target = self.target
        let context = self.context
        runner.keyboard = { [weak self] action in
            guard let self else { throw CancellationError() }
            try await self.deliver(action, to: target, generation: current)
        }
        let progress: @Sendable (MicroAppRunProgress) -> Void = { [weak self] progress in
            // The main queue keeps the order of the updates.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current, case .working = self.session.state else { return }
                    self.session.progress = progress
                }
            }
        }
        task = Task { [weak self] in
            let result = await runner.run(app, values: values, stdin: stdin, context: context, progress: progress)
            guard let self, self.generation == current, !Task.isCancelled else { return }
            self.task = nil
            self.outcome = .ran(succeeded: result.isSuccess)
            // A `keys` or `paste` step without Accessibility: the Accessibility help says what to do.
            if self.accessibilityAsked == current, case .stepFailed = result {
                self.close()
                return
            }
            self.present(MicroAppResultPlan.make(app: app, result: result, outputLimit: runner.outputLimit,
                                                 timeLimit: runner.timeLimit(for: app)), title: app.shownName)
        }
    }

    /// A `keys` or `paste` step: the panel goes away until the result, so the keys reach the app.
    private func deliver(_ action: MicroAppKeyboardAction, to target: MicroAppTarget?, generation current: Int) async throws {
        guard generation == current else { throw CancellationError() }
        panel?.orderOut(nil)
        do {
            try await keyboard.send(action, to: target)
        } catch where error.needsAccessibility {
            if generation == current {
                accessibilityAsked = current
                onAccessibilityNeeded?()
            }
            throw error
        }
    }

    private func present(_ plan: MicroAppResultPlan, title: String = "SwiftKey") {
        if let text = plan.clipboard {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        if let text = plan.app {
            return paste(text, keepOnClipboard: plan.clipboard != nil, plan: plan, title: title)
        }
        switch plan.show {
        case .nothing:
            close()
        case .toast(let message):
            close()
            onToast?(message)
        case .panel(let content):
            show(.result(content))
        }
    }

    /// The `app` output: the panel closes and the result goes into the app. When that fails, the
    /// result stays on the clipboard and the error says so.
    private func paste(_ text: String, keepOnClipboard: Bool, plan: MicroAppResultPlan, title: String) {
        let target = self.target
        close()
        let keyboard = self.keyboard
        let current = generation
        Task { [weak self] in
            do {
                try await keyboard.send(.paste(text, keepOnClipboard: keepOnClipboard), to: target)
                guard let self, self.generation == current, case .toast(let message) = plan.show else { return }
                self.onToast?(message)
            } catch {
                guard let self, self.generation == current else { return }
                if !keepOnClipboard {
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(text, forType: .string)
                }
                if error.needsAccessibility {
                    self.onAccessibilityNeeded?()
                    self.onToast?("Not pasted. The result is on the clipboard.")
                    return
                }
                self.present(MicroAppResultPlan.error(title: title, message: "\(error.localizedDescription) The result is on the clipboard."))
            }
        }
    }

    /// A key of the panel: ↩, ⌘O or Esc.
    func handle(_ key: MicroAppFlowPanel.Key) {
        switch (session.state, key) {
        case (.form, .enter):
            submitForm()
        case (.form, .toggleOptional):
            session.form?.toggleOptional()
        case (.result(let content), .enter):
            copyAll(content)
            close()
        case (_, .escape):
            close()
        default:
            break
        }
    }

    private func copyAll(_ content: MicroAppPanelContent) {
        pasteboard.clearContents()
        // The plain result: console text (and every error) without its escape codes.
        pasteboard.setString(content.plainText, forType: .string)
    }

    // MARK: Panel

    private func show(_ state: MicroAppFlowSession.State) {
        let panel = self.panel ?? makePanel()
        guard presentsWindow else {
            session.state = state
            return
        }
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                // Near the upper third, like launcha.
                let top = visible.maxY - max(40, visible.height * 0.16)
                let height = max(240, min(CGFloat(MicroAppFormLayout.panelCap), top - visible.minY - 20))
                let width: CGFloat = 640
                panel.setFrame(NSRect(x: visible.midX - width / 2, y: top - height, width: width, height: height), display: false)
            }
        }
        session.formMaxHeight = CGFloat(MicroAppFormLayout.maxFormHeight(panelHeight: Double(panel.frame.height)))
        session.state = state
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> MicroAppFlowPanel {
        let panel = MicroAppFlowPanel()
        panel.delegate = self
        panel.onKey = { [weak self] key in self?.handle(key) }
        let view = MicroAppFlowView(session: session,
                                    onCopyAll: { [weak self] in
                                        guard let self, case .result(let content) = self.session.state else { return }
                                        self.copyAll(content)
                                        self.close()
                                    },
                                    onDismiss: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// A click elsewhere closes the parameter and the result panel. A running command keeps
    /// running; its result comes back to the front.
    func windowDidResignKey(_ notification: Notification) {
        switch session.state {
        case .form, .result: close()
        case .working, .closed: break
        }
    }
}

/// Why a start found nothing to run, in words for the error panel.
struct MicroAppStartProblem: Error {
    var message: String
}

private extension MicroAppRunResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
