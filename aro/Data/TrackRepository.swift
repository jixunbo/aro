import Combine
import Foundation

@MainActor
final class TrackRepository: ObservableObject {
    static let shared = TrackRepository()

    @Published private(set) var todayPoints: [TrackPoint] = []
    @Published private(set) var days: [TrackDay] = []
    @Published private(set) var lifetime: LifetimeStats = .empty
    @Published private(set) var overviewPoints: [TrackPoint] = []
    @Published private(set) var databaseBytes: Int64 = 0
    @Published private(set) var isLoading = false

    private let database = TrackDatabase.shared

    private init() {}

    func refresh(includeOverview: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        let database = self.database
        Task.detached(priority: .utility) {
            let today = database.points(on: Date())
            let days = database.trackDays()
            let lifetime = database.lifetimeStats()
            let overview = includeOverview ? database.overviewPoints() : []
            let bytes = database.fileSize()
            await MainActor.run {
                self.todayPoints = today
                self.days = days
                self.lifetime = lifetime
                if includeOverview { self.overviewPoints = overview }
                self.databaseBytes = bytes
                self.isLoading = false
            }
        }
    }

    func loadPoints(on date: Date) async -> [TrackPoint] {
        let database = self.database
        return await Task.detached(priority: .userInitiated) {
            database.points(on: date)
        }.value
    }

    func didInsertPoint() {
        refresh()
    }

    func deleteEverything() {
        database.deleteAll()
        todayPoints = []
        days = []
        lifetime = .empty
        overviewPoints = []
        databaseBytes = 0
    }
}
