import Foundation
import Network
import os

/// Current network path, for "Wi-Fi only" iCloud downloads and skipping the judge when offline.
nonisolated final class Reachability: Sendable {
    struct State: Sendable, Equatable {
        var isOnline: Bool
        var isExpensive: Bool
    }

    static let shared = Reachability()

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: State(isOnline: true, isExpensive: false))

    private init() {
        let state = self.state
        monitor.pathUpdateHandler = { path in
            state.withLock { $0 = State(isOnline: path.status == .satisfied, isExpensive: path.isExpensive) }
        }
        monitor.start(queue: DispatchQueue(label: "app.eymra.reachability"))
    }

    var current: State { state.withLock { $0 } }
}
