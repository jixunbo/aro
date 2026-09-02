import Foundation
import WatchConnectivity

@MainActor
final class PhoneConnectivity: NSObject, ObservableObject {
    static let shared = PhoneConnectivity()
    private static let trackPublishInterval: TimeInterval = 5 * 60
    private static let trackDistanceThreshold: Double = 250

    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var lastError: String?

    private var session: WCSession?
    private var activationInProgress = false
    private var activationWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var pendingRequests: [UUID: CheckedContinuation<BatterySnapshot?, Never>] = [:]
    private var pendingTrackSnapshot: TrackComplicationSnapshot?
    private var lastPublishedTrackSnapshot: TrackComplicationSnapshot?

    private override init() {
        super.init()
    }

    /// Activates WatchConnectivity without requesting live battery data.
    /// Callers must use `freshestSnapshot()` for an explicit live request.
    func activate() {
        guard WCSession.isSupported() else { return }

        if session == nil {
            let session = WCSession.default
            self.session = session
            session.delegate = self
        }
        startActivationIfNeeded()
        refreshSessionState()
    }

    /// Refreshes passive session metadata only. This never sends a message.
    func appBecameActive() {
        activate()
        refreshSessionState()
    }

    /// Queues the latest route summary for the Watch face complication.
    /// This never activates WatchConnectivity on its own, preserving Core Location cold-launch isolation.
    func publishTrackComplication(points: [TrackPoint], force: Bool = false) {
        pendingTrackSnapshot = TrackMath.trackComplicationSnapshot(of: points)
        flushTrackComplication(force: force)
    }

    func freshestSnapshot(timeoutSeconds: UInt64 = 3) async -> BatterySnapshot? {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        activate()
        guard let session else { return BatteryStore.shared.snapshot }

        if session.activationState != .activated {
            let activated = await waitForActivation(timeoutNanoseconds: nanoseconds(until: deadline))
            guard activated else { return BatteryStore.shared.snapshot }
        }

        ingestReceivedApplicationContext(from: session)
        refreshSessionState()
        guard session.isReachable else { return BatteryStore.shared.snapshot }
        let remainingNanoseconds = nanoseconds(until: deadline)
        guard remainingNanoseconds > 0 else { return BatteryStore.shared.snapshot }

        let token = UUID()
        return await withCheckedContinuation { continuation in
            pendingRequests[token] = continuation
            let message = [PayloadKey.command: PayloadKey.requestBattery]

            session.sendMessage(message, replyHandler: { payload in
                Task { @MainActor in
                    let fresh = BatteryStore.shared.update(from: payload)
                    self.lastError = nil
                    self.finishRequest(token, with: fresh ?? BatteryStore.shared.snapshot)
                }
            }, errorHandler: { error in
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                    self.finishRequest(token, with: BatteryStore.shared.snapshot)
                }
            })

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: remainingNanoseconds)
                self.finishRequest(token, with: BatteryStore.shared.snapshot)
            }
        }
    }

    private func waitForActivation(timeoutNanoseconds: UInt64) async -> Bool {
        guard let session else { return false }
        if session.activationState == .activated { return true }
        guard timeoutNanoseconds > 0 else { return false }

        let token = UUID()
        return await withCheckedContinuation { continuation in
            activationWaiters[token] = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self.finishActivationWaiter(token, activated: false)
            }
        }
    }

    private func nanoseconds(until deadline: Date) -> UInt64 {
        UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000)
    }

    private func finishActivationWaiter(_ token: UUID, activated: Bool) {
        guard let continuation = activationWaiters.removeValue(forKey: token) else { return }
        continuation.resume(returning: activated)
    }

    private func finishActivationWaiters(activated: Bool) {
        let waiters = activationWaiters
        activationWaiters.removeAll()
        waiters.values.forEach { $0.resume(returning: activated) }
    }

    private func finishRequest(_ token: UUID, with snapshot: BatterySnapshot?) {
        guard let continuation = pendingRequests.removeValue(forKey: token) else { return }
        continuation.resume(returning: snapshot)
    }

    private func receive(_ payload: [String: Any]) {
        _ = BatteryStore.shared.update(from: payload)
        lastError = nil
    }

    private func ingestReceivedApplicationContext(from session: WCSession) {
        guard !session.receivedApplicationContext.isEmpty else { return }
        receive(session.receivedApplicationContext)
    }

    private func flushTrackComplication(force: Bool) {
        guard let session,
              session.activationState == .activated,
              session.isWatchAppInstalled,
              let snapshot = pendingTrackSnapshot else {
            return
        }

        if !force, let previous = lastPublishedTrackSnapshot {
            let elapsed = snapshot.updatedAt.timeIntervalSince(previous.updatedAt)
            let distanceDelta = abs(snapshot.distanceMeters - previous.distanceMeters)
            let dayChanged = !Calendar.autoupdatingCurrent.isDate(snapshot.dayStart, inSameDayAs: previous.dayStart)
            let routeStarted = previous.segments.isEmpty && !snapshot.segments.isEmpty
            guard dayChanged
                    || routeStarted
                    || elapsed >= Self.trackPublishInterval
                    || distanceDelta >= Self.trackDistanceThreshold else {
                return
            }
        }

        let payload = snapshot.payload
        guard !payload.isEmpty else { return }
        do {
            try session.updateApplicationContext(payload)
            lastPublishedTrackSnapshot = snapshot
            pendingTrackSnapshot = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startActivationIfNeeded(force: Bool = false) {
        guard let session, !activationInProgress else { return }
        guard session.activationState != .activated else { return }
        guard force || session.activationState == .notActivated else { return }

        activationInProgress = true
        session.activate()
    }

    private func refreshSessionState() {
        guard let session else { return }
        activationState = session.activationState
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationInProgress = false
            self.lastError = error?.localizedDescription
            if activationState == .activated {
                self.ingestReceivedApplicationContext(from: session)
                self.flushTrackComplication(force: true)
            }
            self.refreshSessionState()
            self.finishActivationWaiters(activated: activationState == .activated)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshSessionState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.activationInProgress = false
            self.startActivationIfNeeded(force: true)
            self.refreshSessionState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshSessionState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshSessionState()
            self.flushTrackComplication(force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.receive(message)
            replyHandler(["received": true])
        }
    }
}
