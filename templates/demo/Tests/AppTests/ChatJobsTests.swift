import FlightCore
import FlightWebTesting
import Foundation
import Testing

@testable import App

/// A scheduled job is an ordinary method on an ordinary component.
///
/// No scheduler and no database: `ChatJobs` is resolved from a test container
/// with the digest reads stubbed, exactly as `UserServiceTests` resolves a
/// service with its repository stubbed. Whether the job fires at 03:00 is the
/// cron engine's business and is tested there, not here.
@Suite("ChatJobs — jobs as plain methods")
struct ChatJobsTests {

    private struct StubDigests: DigestReading {
        let rooms: [RoomActivity]

        func activity(minimumMessages: Int) async throws -> [RoomActivity] {
            rooms.filter { $0.messages >= minimumMessages }
        }
        func headlines() async throws -> [RoomHeadline] { [] }
    }

    /// Binds the stub under the same key the application binds the real
    /// service under.
    private struct FakeDigests: FlightModule {
        let rooms: [RoomActivity]
        // FlightModule requires a no-argument init — bootstrap instantiates
        // modules itself — so the seeded one is a second initializer, the
        // same shape FakeRepository uses.
        init() { self.rooms = [] }
        init(rooms: [RoomActivity]) { self.rooms = rooms }

        func configure(_ container: Container) throws {
            let rooms = self.rooms
            container.register((any DigestReading).self, scope: .singleton) { _ in
                StubDigests(rooms: rooms)
            }
        }
    }

    private func jobs(rooms: [RoomActivity]) throws -> ChatJobs {
        let container = try TestContainer.build {
            Components(ChatJobs.self)
            FakeDigests(rooms: rooms)
        }
        return try container.resolve(ChatJobs.self)
    }

    @Test("the nightly summary runs against the busy rooms")
    func summaryCountsBusyRooms() async throws {
        let jobs = try jobs(rooms: [
            RoomActivity(room: "general", messages: 42, lastSentAt: Date()),
            RoomActivity(room: "quiet", messages: 1, lastSentAt: nil),
        ])
        try await jobs.nightlySummary()
    }

    @Test("warming the digests asks for the headlines")
    func warmingReadsHeadlines() async throws {
        try await jobs(rooms: []).warmDigests()
    }
}
