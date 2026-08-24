import Foundation
import Synchronization

@testable import App

/// A repository that keeps rows in memory.
///
/// This is what makes the suites in this target run with no database: they
/// depend on `UserRepositoryProtocol`, and this satisfies it. There is no mock
/// framework and nothing generated — a fake is a type that conforms.
final class InMemoryUsers: UserRepositoryProtocol, Sendable {
    private let users = Mutex<[User]>([])

    init(_ seed: [User] = []) { users.withLock { $0 = seed } }

    /// What the suite wrote, for asserting on effects rather than only on
    /// what a handler returned.
    var stored: [User] { users.withLock { $0 } }

    func all() async throws -> [User] { users.withLock { $0 } }

    func find(byID id: UUID) async throws -> User? {
        users.withLock { $0.first { $0.id == id } }
    }

    func find(byEmail email: String) async throws -> User? {
        users.withLock { $0.first { $0.email == email } }
    }

    func create(name: String, email: String) async throws -> User {
        let user = User(
            id: UUID(), name: name, email: email, createdAt: Date(), updatedAt: Date())
        users.withLock { $0.append(user) }
        return user
    }
}

/// The one fixture row the suites share.
let ada = User(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    name: "Ada", email: "ada@example.com", createdAt: Date(), updatedAt: Date())
