import Foundation
import Combine

/// Generic undo/redo manager for any state type
final class UndoRedoManager<State>: ObservableObject {

    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private let maxHistorySize: Int

    init(maxHistorySize: Int = 50) {
        self.maxHistorySize = maxHistorySize
    }

    /// Records a new state, clearing redo stack
    func record(_ state: State) {
        undoStack.append(state)
        redoStack.removeAll()

        // Prune old history
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }

        updateFlags()
    }

    /// Undoes to the previous state
    /// - Parameter currentState: The current state to save for redo
    /// - Returns: The previous state, or nil if nothing to undo
    func undo(currentState: State) -> State? {
        guard canUndo else { return nil }

        redoStack.append(currentState)
        let previousState = undoStack.removeLast()

        updateFlags()
        return previousState
    }

    /// Redoes to the next state
    /// - Parameter currentState: The current state to save for undo
    /// - Returns: The next state, or nil if nothing to redo
    func redo(currentState: State) -> State? {
        guard canRedo else { return nil }

        undoStack.append(currentState)
        let nextState = redoStack.removeLast()

        updateFlags()
        return nextState
    }

    /// Clears all history
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateFlags()
    }

    /// Returns the number of undo steps available
    var undoCount: Int {
        undoStack.count
    }

    /// Returns the number of redo steps available
    var redoCount: Int {
        redoStack.count
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
