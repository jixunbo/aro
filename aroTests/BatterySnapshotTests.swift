import XCTest
@testable import aro

final class BatterySnapshotTests: XCTestCase {
    func testPayloadRoundTripClampsBatteryLevel() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try XCTUnwrap(BatterySnapshot(payload: [
            PayloadKey.level: 120,
            PayloadKey.state: BatteryChargeState.charging.rawValue,
            PayloadKey.updatedAt: date.timeIntervalSince1970,
            PayloadKey.deviceName: "测试手表"
        ]))

        XCTAssertEqual(snapshot.level, 100)
        XCTAssertEqual(snapshot.state, .charging)
        XCTAssertEqual(snapshot.updatedAt, date)
        XCTAssertEqual(snapshot.deviceName, "测试手表")
    }

    func testTrackComplicationPayloadRoundTrip() throws {
        let snapshot = TrackComplicationSnapshot(
            distanceMeters: 2_860,
            segments: [
                TrackComplicationSegment(points: [
                    TrackComplicationPoint(x: 0.1, y: 0.2),
                    TrackComplicationPoint(x: 0.8, y: 0.7)
                ])
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            dayStart: Date(timeIntervalSince1970: 1_699_920_000)
        )

        let decoded = try XCTUnwrap(TrackComplicationSnapshot(payload: snapshot.payload))
        XCTAssertEqual(decoded, snapshot)
    }

    func testBatteryStoreKeepsNewestSnapshot() async {
        await MainActor.run {
            let suiteName = "BatterySnapshotTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let store = BatteryStore(defaults: defaults, storageKey: "snapshot")
            let newest = BatterySnapshot(level: 80, state: .unplugged, updatedAt: Date(timeIntervalSince1970: 200))
            let older = BatterySnapshot(level: 20, state: .charging, updatedAt: Date(timeIntervalSince1970: 100))

            store.update(newest)
            let selected = store.update(from: older.payload)

            XCTAssertEqual(store.snapshot, newest)
            XCTAssertEqual(selected, newest)
        }
    }

    func testBatteryStoreAcceptsNewerApplicationContextSnapshot() async {
        await MainActor.run {
            let suiteName = "BatterySnapshotTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let store = BatteryStore(defaults: defaults, storageKey: "snapshot")
            let cached = BatterySnapshot(level: 42, state: .unplugged, updatedAt: Date(timeIntervalSince1970: 100))
            let applicationContext = BatterySnapshot(level: 67, state: .charging, updatedAt: Date(timeIntervalSince1970: 200))

            store.update(cached)
            _ = store.update(from: applicationContext.payload)

            XCTAssertEqual(store.snapshot, applicationContext)
        }
    }
}
