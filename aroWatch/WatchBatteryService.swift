import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class WatchBatteryService: NSObject, ObservableObject {
    static let shared = WatchBatteryService()
    private static let foregroundRefreshInterval: TimeInterval = 5 * 60

    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var isReachable = false

    private var session: WCSession?
    private var timer: Timer?
    private var batteryReadScheduled = false
    private var batteryReadCompletions: [(BatterySnapshot?) -> Void] = []
    private var lastConnectivitySnapshot: BatterySnapshot?

    private override init() {
        super.init()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func startForegroundUpdates() {
        refreshAndSend()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.foregroundRefreshInterval, repeats: true) { _ in
            Task { @MainActor in self.refreshAndSend() }
        }
    }

    func stopForegroundUpdates() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAndSend(completion: (() -> Void)? = nil) {
        sampleBattery { snapshot in
            guard let snapshot else {
                completion?()
                return
            }

            self.snapshot = snapshot
            self.publish(snapshot)
            completion?()
        }
    }

    func refreshAndSendAsync() async {
        await withCheckedContinuation { continuation in
            refreshAndSend {
                continuation.resume()
            }
        }
    }

    private func publish(_ snapshot: BatterySnapshot) {
        if WatchSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WatchSnapshotStore.widgetKind)
        }

        guard let session, session.activationState == .activated else { return }
        guard lastConnectivitySnapshot.map({ !snapshot.hasSameDisplayedValues(as: $0) }) ?? true else { return }

        do {
            try session.updateApplicationContext(snapshot.payload)
            lastConnectivitySnapshot = snapshot
        } catch {
            // The next foreground or background refresh will retry with a newer snapshot.
        }
    }

    private func sampleBattery(completion: @escaping (BatterySnapshot?) -> Void) {
        batteryReadCompletions.append(completion)
        guard !batteryReadScheduled else { return }

        batteryReadScheduled = true
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let rawLevel = device.batteryLevel
            let snapshot: BatterySnapshot?

            if rawLevel >= 0 {
                snapshot = BatterySnapshot(
                    level: Int((rawLevel * 100).rounded()),
                    state: BatteryChargeState(device.batteryState),
                    deviceName: device.name
                )
            } else {
                snapshot = nil
            }

            device.isBatteryMonitoringEnabled = false
            let completions = self.batteryReadCompletions
            self.batteryReadCompletions.removeAll()
            self.batteryReadScheduled = false
            completions.forEach { $0(snapshot) }
        }
    }
}

extension WatchBatteryService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.refreshAndSend()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[PayloadKey.command] as? String == PayloadKey.requestBattery else {
            replyHandler([:])
            return
        }

        Task { @MainActor in
            self.sampleBattery { fresh in
                guard let fresh else {
                    replyHandler(self.snapshot?.payload ?? [:])
                    return
                }

                self.snapshot = fresh
                self.publish(fresh)
                replyHandler(fresh.payload)
            }
        }
    }
}

private extension BatterySnapshot {
    func hasSameDisplayedValues(as other: BatterySnapshot) -> Bool {
        level == other.level && state == other.state && deviceName == other.deviceName
    }
}

private extension BatteryChargeState {
    init(_ state: WKInterfaceDeviceBatteryState) {
        switch state {
        case .unknown: self = .unknown
        case .unplugged: self = .unplugged
        case .charging: self = .charging
        case .full: self = .full
        @unknown default: self = .unknown
        }
    }
}
