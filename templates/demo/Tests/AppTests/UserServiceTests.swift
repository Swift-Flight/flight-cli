import FlightCore
import Foundation
import Testing
@testable import App

/// UserService against a MOCKED repository — through a real (if minimal)
/// Container, because UserService is `@Service` again: its only initializer
/// is the macro-generated `init(_flight:)`, so it's constructed by
/// resolving it, exactly as production does. Only the repository is fake.
@Suite("UserService — repository mocked")
struct UserServiceTests {
    /// UserService on its ordinary @Service path; the mocked repository
    /// bound under the same existential key `AppModule` binds the real one
    /// under (see Main.swift). Everything about UserService's own wiring —
    /// registration, scope, stereotype — is untouched.
    private func makeContainer(repository: MockUserRepository) throws -> Container {
        let container = Container()
        container.register((any UserRepositoryProtocol).self, scope: .scoped) { _ in repository }
        try UserService._flightRegister(container)
        try container.freeze()
        return container
    }

    @Test("find(byID:) returns the matching user from the mocked repository")
    func findByIDReturnsMatch() async throws {
        let ada = User(
            id: UUID(), name: "Ada", email: "ada@example.com",
            createdAt: Date(), updatedAt: Date())
        let container = try makeContainer(repository: MockUserRepository(users: [ada]))

        let found = try await container.withScope { scope in
            try await container.resolve(UserService.self, in: scope).find(byID: ada.id)
        }

        #expect(found == ada)
    }

    @Test("find(byID:) returns nil when the mocked repository has no match")
    func findByIDReturnsNilWhenMissing() async throws {
        let container = try makeContainer(repository: MockUserRepository())

        let found = try await container.withScope { scope in
            try await container.resolve(UserService.self, in: scope).find(byID: UUID())
        }

        #expect(found == nil)
    }
}
