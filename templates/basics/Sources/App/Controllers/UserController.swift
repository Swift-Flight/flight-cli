import FlightCore
import FlightDataCore
import FlightWeb
import Foundation

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

/// CRUD over `users`.
///
/// Handlers stay thin: resolve, delegate, translate failures into status
/// codes. The controller is the only layer that should know what an HTTP
/// status is, and the repository is the only layer that should know SQL.
@Controller
struct UserController {

    @GetMapping("/users")
    func list(_ context: RequestContext) async throws -> [User] {
        try await context.resolve((any UserRepositoryProtocol).self).all()
    }

    @GetMapping("/users/:id")
    func get(_ context: RequestContext) async throws -> User {
        guard let id = context.pathParam("id").flatMap({ UUID(uuidString: $0) }) else {
            throw HTTPError(.badRequest, "user id must be a UUID")
        }
        let users = try context.resolve((any UserRepositoryProtocol).self)
        guard let user = try await users.find(byID: id) else {
            throw HTTPError(.notFound, "no user \(id)")
        }
        return user
    }

    @PostMapping("/users")
    func create(_ context: RequestContext, body: CreateUserRequest) async throws -> Response {
        let users = try context.resolve((any UserRepositoryProtocol).self)

        // Validation runs before any SQL does: a changeset collects the
        // changes, checks them, and only a valid one reaches the database.
        let changeset = Changeset(User.self)
            .change(\.name, body.name)
            .change(\.email, body.email)
            .validate(\.email, .email)
        guard changeset.isValid else {
            throw HTTPError(.badRequest, "invalid user: \(changeset.errors)")
        }
        guard try await users.find(byEmail: body.email) == nil else {
            throw HTTPError(.conflict, "that email is already registered")
        }
        return try .json(await users.create(name: body.name, email: body.email), status: .created)
    }
}
