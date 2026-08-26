import FlightActuator
import FlightCache
import FlightChannels
import FlightCore
import FlightDataPostgres
import FlightPresence
import FlightPubSub
import FlightScheduler
import FlightSchedulerPostgres
import FlightSecurityCore
import FlightTransport
import FlightWeb
import Foundation

/// Flight Security's `Principal` and Flight Channels' `ChannelPrincipal` are
/// deliberately unrelated: Channels has no dependency on Security, so a
/// WebSocket layer can be used with any notion of identity — or none. The two
/// meet in application code, which is here, and the conformance is empty
/// because `Principal` already has everything the protocol asks for.
extension Principal: @retroactive ChannelPrincipal {}

/// Registers everything the build plugin found — every @Component,
/// @Controller, @Service and @Repository in this target — through the one
/// registration pipeline.
struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] {
        [
            PostgresDataModule<PrimaryDataSource>.self,
            FlightPubSubModule.self,
            FlightChannelsModule.self,
            FlightPresenceModule.self,
            FlightCacheModule.self,
            FlightSchedulerModule.self,
            // FlightSecurityModule is deliberately NOT here. It installs its
            // generic OIDC validator unless one is already registered, so it
            // has to configure *after* this module rather than before it —
            // which is what listing it later in `bootstrap` below achieves.
            // Declaring it as a dependency would force the opposite order and
            // fail the container freeze with a duplicate registration.
        ]
    }

    func configure(_ container: Container) throws {
        try flightRegisterAll(container)

        // Order is declared once, here, top to bottom, outermost first —
        // RequestLogging sees the true wall-clock time of everything below
        // it, and Transactions runs before anything that might write, so no
        // handler can begin a unit of work with no coordinator bound.
        container.pipeline {
            RequestLogging.self
            Transactions.self
        }

        // The gateway, and the two things that depend on it. All three are
        // singletons that never capture a request-scoped repository — they
        // open a scope per call instead. See ChatGateway for why.
        container.register(ChatGateway.self, scope: .singleton) { c in
            ChatGateway(container: c)
        }
        container.register((any RoomStore).self, scope: .singleton) { c in
            try c.resolve(ChatGateway.self)
        }
        container.register(RoomDigestService.self, scope: .singleton) { c in
            RoomDigestService(chat: try c.resolve(ChatGateway.self))
        }
        // The read seam scheduled jobs depend on, so a job is testable
        // without a cache or a database behind it.
        container.register((any DigestReading).self, scope: .singleton) { c in
            try c.resolve(RoomDigestService.self)
        }

        // Makes `.once` mean once across every server rather than once per
        // server. This demo runs one process, where the coordinator changes
        // nothing — but registering it is the whole difference between a
        // nightly job that is safe to scale and one that is not, and the
        // scheduler warns at startup when it is missing.
        container.register((any JobCoordinator).self, scope: .singleton) { c in
            // Qualified: data sources are registered under their name so an
            // app with two databases can say which it means. A single-database
            // app never writes the qualifier anywhere else — this is the one
            // place that resolves the pool directly rather than through a
            // scoped connection.
            PostgresJobCoordinator(
                dataSource: try c.resolve(
                    PostgresDataSource.self, qualifier: PrimaryDataSource.name))
        }

        // The bring-your-own-auth seam. FlightSecurityModule installs its
        // generic OIDC validator only if none is registered by the time it
        // configures — so this must run first, which is why that module is
        // listed after this one in `bootstrap` rather than declared as a
        // dependency of it.
        //
        // A real deployment deletes this and configures `security.oidc.*`.
        container.register((any TokenValidator).self, scope: .singleton) { _ in
            DemoTokenValidator()
        }

        // One registration serves every room. Patterns are exact, prefix
        // wildcard, or catch-all, and the most specific match wins; a
        // malformed or duplicate pattern fails bootstrap rather than a join.
        container.registerChannel("room:*") { c in
            RoomChannel(
                broadcaster: try c.resolve(ChannelBroadcaster.self),
                presence: try c.resolve((any Presence).self),
                chat: try c.resolve((any RoomStore).self),
                digests: try c.resolve(RoomDigestService.self))
        }

        // The upgrade request is where identity is established — before the
        // WebSocket exists, while there is still an HTTP response to fail
        // with. Browsers cannot set headers on a WebSocket handshake, so the
        // token arrives as a query parameter; returning nil admits an
        // anonymous socket, which every `join` here then rejects.
        container.registerChannelSocket("/socket") { context in
            guard let token = context.request.queryParam("token") else { return nil }
            return try? await context.resolve((any TokenValidator).self).validate(token)
        }
    }
}

@main
struct Main {
    static func main() async {
        // Steps 1–3: Flight Config (flight.yaml + FLIGHT_* env). Steps 4–9:
        // container, module DAG, freeze, ServiceGroup — request serving
        // starts only after the whole DAG has registered.
        do {
            try await Flight.bootstrap(
                configuration: try Configuration.load(),
                modules: [
                    FlightWebModule<FlightTransport>.self,  // choosing a transport = choosing a module
                    AppModule.self,
                    // After AppModule, so it finds the validator registered
                    // above and stands down instead of installing the OIDC
                    // default.
                    FlightSecurityModule.self,
                    ActuatorModule.self,
                ]
            )
        } catch {
            // Not `main() async throws`. An error escaping `main` is reported
            // by the Swift runtime as "Fatal error: Error raised at top
            // level" followed by a register dump and a backtrace — which is
            // what a new project sees when Postgres is not running or port
            // 8080 is already bound. Those two deserve a line of text and a
            // non-zero exit, not a crash report.
            //
            // `String(reflecting:)` rather than plain interpolation because
            // PostgresNIO's `description` is deliberately redacted — it says
            // "Generic description to prevent accidental leakage" and nothing
            // about what went wrong. The reflected form names the host, the
            // port and the errno. That is safe here specifically: this is a
            // startup failure, so there are no user queries or bind values to
            // leak, and the process is about to exit.
            FileHandle.standardError.write(
                Data("App failed to start: \(String(reflecting: error))\n".utf8))
            exit(1)
        }
    }
}
