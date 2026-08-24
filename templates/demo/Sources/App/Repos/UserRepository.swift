import Foundation
import FlightDataPostgres

/// The one thing signup can fail on that isn't a validation error.
enum SignupError: Error, Sendable {
    case noLobby
}

@Repository(scope: .scoped)
struct UserRepository: UserRepositoryProtocol {
    // flight:hand-registered — resolved through FlightDataPostgres's
    // ambient-scope overloads, not a scanned @Component.
    @Autowired var repo: Repo   // the scope's connection-bound Hangar repo

    func all() async throws -> [User] {
        try await repo.all(User.all.order { $0.createdAt.desc() })
    }

    func find(byID id: UUID) async throws -> User? {
        try await repo.one(User.where { $0.id == id })
    }

    func find(byEmail email: String) async throws -> User? {
        try await repo.one(User.where { $0.email == email })
    }

    /// Stage 7: atomic signup. The lobby announcement is written FIRST so a
    /// duplicate-email failure on the user insert provably rolls it back —
    /// the scoped `Repo` shares @Transactional's connection, so both writes
    /// are inside the transaction.
    @Transactional
    func signup(name: String, email: String) async throws -> User {
        // The lobby is a real row now, not a free-text label, so the
        // announcement needs its id. Rooms are created by the migration's
        // backfill and by ChatRepository.openRoom.
        guard let lobby = try await repo.one(Room.where { $0.slug == "lobby" }) else {
            throw SignupError.noLobby
        }
        try await repo.insert(
            ChatMessage(
                id: UUID(), room: lobby.slug, roomID: lobby.id, sender: "system",
                body: "\(name) joined the demo", sentAt: Date()))
        let now = Date()
        return try await repo.insert(
            User(id: UUID(), name: name, email: email, createdAt: now, updatedAt: now))
    }

    /// Stage 8: dirty-column-only UPDATE (or INSERT) from a changeset —
    /// identity decides which, exactly as the changeset design's driver
    /// boundary specifies.
    func apply(_ changeset: Changeset<User>) async throws {
        if changeset.original == nil {
            try await repo.insert(changeset)
        } else {
            try await repo.update(changeset)
        }
    }
}
