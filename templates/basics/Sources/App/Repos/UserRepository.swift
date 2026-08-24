import FlightDataPostgres
import Foundation

/// Data access, scoped to one request.
///
/// `scope: .scoped` means one instance per request, holding one pooled
/// connection for that request's life. Resolving a repository outside any
/// scope is an error rather than a silently new connection — which is what
/// makes "which connection is this query on" always answerable.
@Repository(scope: .scoped)
struct UserRepository: UserRepositoryProtocol {
    /// The scope's connection-bound query interface.
    @Autowired var repo: Repo

    func all() async throws -> [User] {
        try await repo.all(User.all.order { $0.createdAt.desc() })
    }

    func find(byID id: UUID) async throws -> User? {
        try await repo.one(User.where { $0.id == id })
    }

    func find(byEmail email: String) async throws -> User? {
        try await repo.one(User.where { $0.email == email })
    }

    func create(name: String, email: String) async throws -> User {
        let now = Date()
        return try await repo.insert(
            User(id: UUID(), name: name, email: email, createdAt: now, updatedAt: now))
    }
}
