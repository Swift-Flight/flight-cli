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

    /// Wrapped in `Transactor.run`, like `POST /chatUser` and for the same
    /// reason: `UserRepository.signup` is `@Transactional` and writes the
    /// lobby announcement before the user, so a duplicate email has to roll
    /// the announcement back. Without a coordinator bound around the call it
    /// still *runs* — every write lands, nothing rolls back, and the
    /// guarantee in that method's own doc comment is quietly false.
    ///
    /// This route did not bind one until a demo application built on Flight
    /// hit the same thing. Flight Core now warns once per process when a
    /// `@Transactional` method runs with no coordinator, which is the signal
    /// that was missing.
    @PostMapping("/user")
    func upsertUser(_ context: RequestContext, body: CreateUserRequest) async throws -> Response {
        context.logger.info("Creating user")
        let service = try context.resolve(UserService.self)
        let transactor = try context.resolve(Transactor.self)

        if let user = try await service.find(byEmail: body.email) {
            let changeset = Changeset(original: user)
            .change(\.email, body.email)
            .change(\.name, body.name)
            .validate(\.email, .email)
            context.logger.info("Upserting user")
            guard changeset.isValid else { throw HTTPError(.badRequest, "Invalid User") }
            let updated = try await transactor.run(in: context.scope) {
                try await service.update(id: user.id, changeset: changeset)
            }
            return try .json(updated)
        }

        let created = try await transactor.run(in: context.scope) {
            try await service.signup(name: body.name, email: body.email)
        }
        return try .json(created)
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
