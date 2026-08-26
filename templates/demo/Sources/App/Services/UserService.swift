import FlightCore
import FlightDataPostgres
import Foundation

/// The business-logic layer between controllers and data access.
///
/// `@Autowired` targets the existential `(any UserRepositoryProtocol)`
/// rather than the concrete `UserRepository` — the seam that makes this type
/// unit-testable. Nothing bridges that key by hand anymore: the registration
/// generator matches this demand against `UserRepository`'s conformance (its
/// only scanned conformer) and synthesizes the bridge into
/// `flightRegisterAll`. Tests bypass `flightRegisterAll` and register a fake
/// under the same key — see `UserServiceTests.swift` /
/// `UserControllerTests.swift` for the two ends of the seam.
@Service(scope: .scoped)
struct UserService {
    @Autowired var repository: (any UserRepositoryProtocol)

    func all() async throws -> [User] {
        try await repository.all()
    }

    func find(byID id: UUID) async throws -> User? {
        try await repository.find(byID: id)
    }

    func find(byEmail email: String) async throws -> User? {
        try await repository.find(byEmail: email)
    }

    /// The @Transactional boundary lives on the repository method; this just
    /// forwards. `Transactions` middleware binds a coordinator around every
    /// request, so this runs in a real transaction whenever it is called
    /// from a handler — see `Web/Transactions.swift`.
    func signup(name: String, email: String) async throws -> User {
        let changeset = Changeset(User.self)
            .change(\.name, name)
            .change(\.email, email)
            .validate(\.email, .email)
        guard changeset.isValid else { throw ChangesetValidationError(errors: changeset.errors) }
        try await repository.apply(changeset)
        return try await repository.find(byEmail: email)!
    }

    func update(id: UUID, changeset: Changeset<User>) async throws -> User? {
        try await repository.apply(changeset)
        return try await repository.find(byID: id)
    }
}
