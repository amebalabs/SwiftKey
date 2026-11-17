@testable import SwiftKeyRuntime
import Foundation
import XCTest

/// Live output is throttled, but the last piece is never lost or late, and pieces never go back.
final class MicroAppThrottleTests: XCTestCase {
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func add(_ data: Data) { lock.withLock { values.append(Int(String(decoding: data, as: UTF8.self))!) } }
        var all: [Int] { lock.withLock { values } }
    }

    func testFinishDeliversTheLastValueAtOnceAndNothingAfter() {
        let throttle = MicroAppThrottle(interval: 0.08)
        let received = Received()
        for n in 1...50 { throttle.submit(Data(String(n).utf8), deliver: { received.add($0) }) }
        throttle.finish(deliver: { received.add($0) })
        XCTAssertEqual(received.all.last, 50, "the last value arrives before finish returns")
        throttle.submit(Data("51".utf8), deliver: { received.add($0) })
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(received.all.last, 50, "nothing arrives after finish")
        XCTAssertEqual(received.all, received.all.sorted(), "values never go back")
    }
}
