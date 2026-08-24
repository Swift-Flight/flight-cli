import FlightActuator
import FlightCache
import FlightChannels
import FlightCore
import FlightDataPostgres
import FlightPresence
import FlightPubSub
import FlightSecurityCore
import FlightTransport
import FlightWeb

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
            FlightSecurityModule.self,
        ]
    }

    func configure(_ container: Container) throws {
        try flightRegisterAll(container)

        // Middleware are components too: same pipeline, hand-registered here.
        container.registerMiddleware("request-log", order: 0) { context in
            context.logger.info("→ \(context.request.method.rawValue) \(context.request.path)")
            return .continue
        }

        // Manual registration — the escape hatch beside the macro pipeline,
        // for components whose factory needs the Container itself.
        container.register(Transactor.self, scope: .singleton) { c in
            Transactor(container: c)
        }

        // The bring-your-own-auth seam. Registering a validator *before*
        // FlightSecurityModule configures means the module finds one already
        // present and does not install its OIDC default. A real deployment
        // deletes this line and configures `security.oidc.*` instead.
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
                chat: try c.resolve(ChatRepository.self),
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
    static func main() async throws {
        // Steps 1–3: Flight Config (flight.yaml + FLIGHT_* env). Steps 4–9:
        // container, module DAG, freeze, ServiceGroup — request serving
        // starts only after the whole DAG has registered.
        try await Flight.bootstrap(
            configuration: try Configuration.load(),
            modules: [
                FlightWebModule<FlightTransport>.self,  // choosing a transport = choosing a module
                AppModule.self,
                ActuatorModule.self,
            ]
        )
    }
}
