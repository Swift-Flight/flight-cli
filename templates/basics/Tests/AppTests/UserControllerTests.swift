import FlightCore
import FlightWeb
import FlightWebTesting
import Foundation
import Synchronization
import Testing

@testable import App

/// An in-memory repository, so this suite exercises the real controller, the
/// real routing, the real dependency injection, and the real JSON encoding
/// with no database in the loop.
private final class InMemoryUsers: UserRepositoryProtocol, Sendable {
    private let users = Mutex<[User]>([])

    init(_ seed: [User] = []) { users.withLock { $0 = seed } }

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

/// Only the bottommost seam is swapped. The controller is registered through
/// its ordinary macro-generated thunk, exactly as `flightRegisterAll` would
/// register it in production.
private struct TestModule: FlightModule {
    static let ada = User(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Ada", email: "ada@example.com", createdAt: Date(), updatedAt: Date())

    let users: InMemoryUsers

    init() { self.users = InMemoryUsers([Self.ada]) }

    func configure(_ container: Container) throws {
        try UserController._flightRegister(container)
        let users = self.users
        container.register((any UserRepositoryProtocol).self, scope: .scoped) { _ in users }
    }
}

@Suite("User routes — repository faked, everything above it real")
struct UserControllerTests {

    private func client() throws -> TestClient {
        try TestClient(container: TestContainer.build { TestModule() })
    }

    @Test("listing returns the seeded user")
    func list() async throws {
        let client = try client()
        let response = await client.get("/users")
        #expect(response.status == .ok)
        #expect(try response.decodeJSON([UserPayload].self).count == 1)
    }

    @Test("fetching by id returns that user")
    func getByID() async throws {
        let client = try client()
        let response = await client.get("/users/\(TestModule.ada.id)")
        #expect(response.status == .ok)
        #expect(try response.decodeJSON(UserPayload.self).email == "ada@example.com")
    }

    @Test("an id that is not a UUID is a 400, not a 500")
    func malformedID() async throws {
        let client = try client()
        #expect(await client.get("/users/not-a-uuid").status == .badRequest)
    }

    @Test("an unknown id is a 404")
    func unknownID() async throws {
        let client = try client()
        #expect(await client.get("/users/\(UUID())").status == .notFound)
    }

    @Test("creating a user returns 201 and the new row")
    func create() async throws {
        let client = try client()
        let response = try await client.post(
            "/users", json: CreateUserRequest(name: "Grace", email: "grace@example.com"))
        #expect(response.status == .created)
        #expect(try response.decodeJSON(UserPayload.self).name == "Grace")
    }

    @Test("an invalid email is refused before any SQL would run")
    func invalidEmail() async throws {
        let client = try client()
        let response = try await client.post(
            "/users", json: CreateUserRequest(name: "Nope", email: "not-an-email"))
        #expect(response.status == .badRequest)
    }

    @Test("a duplicate email is a conflict, not a second row")
    func duplicateEmail() async throws {
        let client = try client()
        let response = try await client.post(
            "/users", json: CreateUserRequest(name: "Ada Again", email: "ada@example.com"))
        #expect(response.status == .conflict)
    }
}

/// Entities are `Encodable` but deliberately not `Decodable`: once an
/// association has crossed the wire as `null`, "not preloaded" and "preloaded
/// and empty" are indistinguishable, and the type refuses to guess. Models go
/// out as JSON; what comes back in is a type of its own.
private struct UserPayload: Decodable {
    let id: UUID
    let name: String
    let email: String
}
