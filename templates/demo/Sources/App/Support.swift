import FlightCore
import FlightDataPostgres

/// Binds Scope.active + the Postgres transaction coordinator (both
/// task-locals) around a unit of work in an existing scope — the request
/// scope, here. Without this, @Transactional methods run under Flight Core's
/// documented no-op default: they execute, but atomicity silently isn't
/// there. Handlers don't hold the Container directly, so this component captures
/// it once at registration.
struct Transactor: Sendable {
    let container: Container

    func run<T>(in scope: Scope, _ body: () async throws -> T) async throws -> T {
        try await container.withPostgresTransactions(in: scope, body)
    }
}
