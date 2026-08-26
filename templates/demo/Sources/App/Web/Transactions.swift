import FlightCore
import FlightDataPostgres
import FlightWeb

/// Binds `Scope.active` and the Postgres transaction coordinator around
/// every request, so `@Transactional` means something.
///
/// Without this, a `@Transactional` method still *runs* — every write
/// lands, nothing rolls back, and the guarantee in that method's own doc
/// comment is quietly false. A demo application built on Flight shipped
/// exactly that bug, in a single handler that forgot to bind a coordinator
/// by hand; `@Middleware` exists so no handler has to remember to.
@Middleware
struct Transactions: Sendable {
    @Autowired var container: Container

    func handle(_ context: RequestContext, next: Next) async throws -> Response {
        // Not for WebSocket upgrades — a request scope normally dies when
        // the response is written, but an upgraded one lives as long as
        // the socket, and binding here would check out a pool connection
        // for as long as the tab stays open.
        guard context.request.headers[.upgrade] == nil else {
            return try await next(context)
        }
        do {
            return try await container.withPostgresTransactions(in: context.scope) {
                try await next(context)
            }
        } catch let error as DataSourceError {
            context.logger.warning("pool exhausted: \(error)")
            return Response.status(.serviceUnavailable).settingHeader(.retryAfter, "1")
        } catch {
            context.logger.error("could not bind transactions: \(error)")
            return .status(.internalServerError)
        }
    }
}
