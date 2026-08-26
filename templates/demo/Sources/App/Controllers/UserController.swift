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

    /// `UserRepository.signup` is `@Transactional` and writes the lobby
    /// announcement before the user, so a duplicate email has to roll the
    /// announcement back. That guarantee depends on a coordinator being
    /// bound around this call — which, since `Transactions` middleware
    /// binds one around every request, this handler gets for free rather
    /// than needing to ask for.
    ///
    /// A demo application built on Flight shipped a route that forgot to
    /// bind one by hand: every write still landed, nothing rolled back, and
    /// the guarantee in `signup`'s own doc comment was quietly false.
    /// `@Middleware` is what turned "every handler must remember" into
    /// "nothing to remember" — see `Web/Transactions.swift`.
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
            let updated = try await service.update(id: user.id, changeset: changeset)
            return try .json(updated)
        }

        let created = try await service.signup(name: body.name, email: body.email)
        return try .json(created)
    }

    @PostMapping("/chatUser")
    func createUser(_ context: RequestContext, body: CreateUserRequest) async throws -> Response {
        let service = try context.resolve(UserService.self)
        let user = try await service.signup(name: body.name, email: body.email)
        return try .json(user, status: .created)
    }
}
