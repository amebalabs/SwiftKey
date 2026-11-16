import Testing
import Foundation
@testable import SwiftKey

@Suite("Undo/Redo Manager")
struct UndoRedoManagerTests {

    @Test("Initial state has no undo or redo")
    func initialState() {
        let manager = UndoRedoManager<String>()

        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
        #expect(manager.undoCount == 0)
        #expect(manager.redoCount == 0)
    }

    @Test("Recording state enables undo")
    func recordEnablesUndo() {
        let manager = UndoRedoManager<String>()

        manager.record("state1")

        #expect(manager.canUndo)
        #expect(!manager.canRedo)
        #expect(manager.undoCount == 1)
    }

    @Test("Undo returns previous state")
    func undoReturnsPreviousState() {
        let manager = UndoRedoManager<String>()

        manager.record("state1")

        let previousState = manager.undo(currentState: "state2")

        #expect(previousState == "state1")
        #expect(!manager.canUndo)
        #expect(manager.canRedo)
    }

    @Test("Redo returns next state")
    func redoReturnsNextState() {
        let manager = UndoRedoManager<String>()

        manager.record("state1")
        _ = manager.undo(currentState: "state2")

        let nextState = manager.redo(currentState: "state1")

        #expect(nextState == "state2")
        #expect(manager.canUndo)
        #expect(!manager.canRedo)
    }

    @Test("Recording clears redo stack")
    func recordClearsRedoStack() {
        let manager = UndoRedoManager<String>()

        manager.record("state1")
        _ = manager.undo(currentState: "state2")
        #expect(manager.canRedo)

        manager.record("state3")

        #expect(!manager.canRedo)
        #expect(manager.redoCount == 0)
    }

    @Test("Clear removes all history")
    func clearRemovesHistory() {
        let manager = UndoRedoManager<String>()

        manager.record("state1")
        manager.record("state2")
        _ = manager.undo(currentState: "state3")

        manager.clear()

        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
        #expect(manager.undoCount == 0)
        #expect(manager.redoCount == 0)
    }

    @Test("Respects max history size")
    func respectsMaxHistorySize() {
        let manager = UndoRedoManager<Int>(maxHistorySize: 3)

        for i in 1 ... 5 {
            manager.record(i)
        }

        #expect(manager.undoCount == 3)
    }

    @Test("Multiple undo operations work correctly")
    func multipleUndoOperations() {
        let manager = UndoRedoManager<String>()

        manager.record("A")
        manager.record("B")
        manager.record("C")

        let fromC = manager.undo(currentState: "D")
        let fromB = manager.undo(currentState: "C")
        let fromA = manager.undo(currentState: "B")

        #expect(fromC == "C")
        #expect(fromB == "B")
        #expect(fromA == "A")
        #expect(!manager.canUndo)
        #expect(manager.redoCount == 3)
    }

    @Test("Undo with empty stack returns nil")
    func undoEmptyStackReturnsNil() {
        let manager = UndoRedoManager<String>()

        let result = manager.undo(currentState: "current")

        #expect(result == nil)
    }

    @Test("Redo with empty stack returns nil")
    func redoEmptyStackReturnsNil() {
        let manager = UndoRedoManager<String>()

        let result = manager.redo(currentState: "current")

        #expect(result == nil)
    }
}
