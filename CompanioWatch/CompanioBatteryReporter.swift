import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class CompanioBatteryReporter: NSObject, ObservableObject {
    static let shared = CompanioBatteryReporter()

    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var isReachable = false

    private var session: WCSession?
    private var timer: Timer?

    private override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func startForegroundUpdates() {
        refreshAndSend()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refreshAndSend() }
        }
    }

    func stopForegroundUpdates() {
        timer?.invalidate()
        timer = nil
        refreshAndSend()
    }

    func refreshAndSend(completion: (() -> Void)? = nil) {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let rawLevel = device.batteryLevel
            guard rawLevel >= 0 else {
                completion?()
                return
            }

            let snapshot = BatterySnapshot(
                level: Int((rawLevel * 100).rounded()),
                state: BatteryChargeState(device.batteryState),
                deviceName: device.name
            )
            self.snapshot = snapshot
            self.publish(snapshot)
            completion?()
        }
    }

    private func publish(_ snapshot: BatterySnapshot) {
        if WatchSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WatchSnapshotStore.widgetKind)
        }

        guard let session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(snapshot.payload)
        } catch {
            // The next foreground or background refresh will retry with a newer snapshot.
        }
    }
}

extension CompanioBatteryReporter: WCSessionDelegate {
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
            let device = WKInterfaceDevice.current()
            device.isBatteryMonitoringEnabled = true
            let rawLevel = device.batteryLevel
            guard rawLevel >= 0 else {
                replyHandler(self.snapshot?.payload ?? [:])
                return
            }

            let fresh = BatterySnapshot(
                level: Int((rawLevel * 100).rounded()),
                state: BatteryChargeState(device.batteryState),
                deviceName: device.name
            )
            self.snapshot = fresh
            self.publish(fresh)
            replyHandler(fresh.payload)
        }
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
