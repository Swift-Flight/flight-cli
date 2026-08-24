import FlightCore
import FlightDataPostgres
import Foundation

/// Bridges long-lived components to request-scoped data access.
///
/// `ChatRepository` is `.scoped`: one instance per request, holding one pooled
/// connection for that request's life. That is the right lifetime for a
/// repository and the wrong one for anything that outlives a request — a
/// singleton that captured one would hold a single connection forever, and a
/// channel that captured one at join time would keep it for the life of a
/// WebSocket.
///
/// So neither captures a repository. They hold this instead, and it opens a
/// scope per call. The cost is a pooled connection acquired and released
/// around each operation; the alternative is a connection leak that only shows
/// up under load.
///
/// It satisfies `RoomStore`, so `RoomChannel` is unchanged and its tests still
/// swap in an in-memory fake.
struct ChatGateway: RoomStore, Sendable {
    let container: Container

    private func withRepository<T>(_ body: (ChatRepository) async throws -> T) async throws -> T {
        try await container.withPostgresScope { scope in
            try await body(container.resolve(ChatRepository.self, in: scope))
        }
    }

    // MARK: RoomStore

    func room(slug: String, messageLimit: Int) async throws -> Room? {
        try await withRepository { try await $0.room(slug: slug, messageLimit: messageLimit) }
    }

    func authorIDs(forNames names: [String]) async throws -> [String: UUID] {
        try await withRepository { try await $0.authorIDs(forNames: names) }
    }

    func post(_ messages: [ChatMessage]) async throws -> [ChatMessage] {
        try await withRepository { try await $0.post(messages) }
    }

    // MARK: Aggregates, for the cached digests

    func activity(minimumMessages: Int) async throws -> [RoomActivity] {
        try await withRepository { try await $0.activity(minimumMessages: minimumMessages) }
    }

    func headlines() async throws -> [RoomHeadline] {
        try await withRepository { try await $0.headlines() }
    }
}
