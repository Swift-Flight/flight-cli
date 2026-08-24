import FlightCore
import FlightWeb
import FlightWebTesting
import Foundation
import Testing
@testable import App

/// A test-only module: mounts the REAL `UserController` and the REAL
/// `UserService` — both via their ordinary macro-generated
/// `_flightRegister` thunks, exactly as `flightRegisterAll` would in
/// production. Only the bottommost seam is swapped: the existential
/// `(any UserRepositoryProtocol)` key resolves to `MockUserRepository`
/// instead of `AppModule`'s real, Postgres-backed bridge. No database
/// anywhere in this suite.
private struct TestModule: FlightModule {
    static let ada = User(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Ada", email: "ada@example.com", createdAt: Date(), updatedAt: Date())

    func configure(_ container: Container) throws {
        try UserController._flightRegister(container)
        try UserService._flightRegister(container)
        container.register((any UserRepositoryProtocol).self, scope: .scoped) { _ in
            MockUserRepository(users: [Self.ada])
        }
    }
}

/// UserController against a MOCKED UserService — dispatched through
/// TestClient (in-process, no socket), so routing, middleware, DI, and JSON
/// encoding are all exercised for real; only Postgres is out of the loop.
@Suite("UserController — repository mocked, everything above it real")
struct UserControllerTests {
    @Test("GET /user/:id returns the mocked user as JSON")
    func getUserReturnsMockedUser() async throws {
        let client = try TestClient(container: TestContainer.build { TestModule() })

        let response = await client.get("/user/\(TestModule.ada.id)")

        #expect(response.status == .ok)
        // Decoded into a wire-shaped struct, not back into `User`. An entity
        // with associations is Encodable but deliberately not Decodable:
        // `Loadable` cannot tell "association not preloaded" from "preloaded
        // and empty" once both have crossed the wire as `null`, so the type
        // refuses to guess. Models go out as JSON; what comes back in is a
        // type of its own.
        let decoded = try response.decodeJSON(UserPayload.self)
        #expect(decoded.id == TestModule.ada.id)
        #expect(decoded.name == TestModule.ada.name)
        #expect(decoded.email == TestModule.ada.email)
        #expect(decoded.authored == nil)
    }

    @Test("GET /user/:id 404s when the mocked repository has no match")
    func getUserReturnsNotFoundWhenMissing() async throws {
        let client = try TestClient(container: TestContainer.build { TestModule() })

        let response = await client.get("/user/\(UUID())")

        #expect(response.status == .notFound)
    }
}

/// The JSON shape `User` encodes to — the read side of the seam described in
/// `getUserReturnsMockedUser`.
private struct UserPayload: Decodable {
    let id: UUID
    let name: String
    let email: String
    let authored: [String]?
}
