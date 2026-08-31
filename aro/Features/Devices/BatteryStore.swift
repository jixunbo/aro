import Foundation

@MainActor
final class BatteryStore: ObservableObject {
    static let shared = BatteryStore()

    @Published private(set) var snapshot: BatterySnapshot?

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "latestAppleWatchBatterySnapshot"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let cached = try? JSONDecoder().decode(BatterySnapshot.self, from: data),
           (0...100).contains(cached.level) {
            snapshot = cached
        }
    }

    @discardableResult
    func update(from payload: [String: Any]) -> BatterySnapshot? {
        guard let snapshot = BatterySnapshot(payload: payload) else { return nil }
        update(snapshot)
        return self.snapshot
    }

    func update(_ snapshot: BatterySnapshot) {
        guard snapshot.updatedAt >= (self.snapshot?.updatedAt ?? .distantPast) else { return }
        self.snapshot = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
