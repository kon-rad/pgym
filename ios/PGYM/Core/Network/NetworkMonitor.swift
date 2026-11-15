import Foundation
import Network
import Observation

/// Whether the phone has a route to the internet. Sign-in and account deletion need one; the
/// screens disable their buttons and say so instead of letting a request spin.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "pgym.network-monitor")

    /// Watches the real network.
    init() {
        isOnline = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    /// A fixed answer, for previews and UI tests.
    init(fixed online: Bool) {
        isOnline = online
        monitor = nil
    }

    deinit {
        monitor?.cancel()
    }
}
