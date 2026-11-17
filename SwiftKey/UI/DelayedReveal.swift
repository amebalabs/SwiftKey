import Foundation

/// Shows a window some time after it opened, so keys typed quickly reach the menu without the
/// menu ever appearing. A menu that closes before the delay passes is never shown.
/// Call it on the main thread; the reveal runs on the main queue.
final class DelayedReveal {
    private var pending: DispatchWorkItem?

    /// True while a reveal waits for its delay.
    var isPending: Bool { pending != nil }

    /// Runs `reveal` after `delay` seconds, or at once for a delay of 0 or less. Starting again
    /// replaces a waiting reveal.
    func start(after delay: TimeInterval, reveal: @escaping () -> Void) {
        cancel()
        guard delay > 0 else {
            reveal()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            reveal()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Forgets a waiting reveal: the window closed first.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
