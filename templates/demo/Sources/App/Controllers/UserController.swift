import Foundation
import FlightCore
import FlightWeb
import FlightDataCore

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

@Controller
struct UserController {
    @GetMapping("/users")
    func listUsers(_ context: RequestContext) async throws -> [User] {
        try await context.resolve(UserService.self).all()
    }

    @GetMapping("/user/:id")
    func getUser(_ context: RequestContext) async throws -> User {
        guard let id = context.pathParam("id").flatMap({ UUID(uuidString: $0) }) else {
            throw HTTPError(.badRequest, "user id must be a UUID")
        }
        guard let user = try await context.resolve(UserService.self).find(byID: id) else {
            throw HTTPError(.notFound, "no user \(id)")
        }
        return user
    }

    @PostMapping("/user")
    func upsertUser(_ context: RequestContext, body: CreateUserRequest) async throws -> Response {
        context.logger.info("Creating user")
        let service = try context.resolve(UserService.self)
        if let user = try await service.find(byEmail: body.email) {
            let changeset = Changeset(original: user)
            .change(\.email, body.email)
            .change(\.name, body.name)
            .validate(\.email, .email)
            context.logger.info("Upserting user")
            guard changeset.isValid else { throw HTTPError(.badRequest, "Invalid User") }
            return try await .json(service.update(id: user.id, changeset: changeset))
        }

        return try await .json(service.signup(name: body.name, email: body.email))
    }

    // The transaction boundary lives here, at the handler, per Flight Data
    // Postgres's own convention: "A handler that already has a request scope
    // binds it" — the request scope (context.scope) only exists at this
    // layer, so this is where Transactor.run wraps the unit of work.
    @PostMapping("/chatUser")
    func createUser(_ context: RequestContext, body: CreateUserRequest) async throws -> Response {
        let service = try context.resolve(UserService.self)
        let transactor = try context.resolve(Transactor.self)
        let user = try await transactor.run(in: context.scope) {
            try await service.signup(name: body.name, email: body.email)
        }
        return try .json(user, status: .created)
    }
}
