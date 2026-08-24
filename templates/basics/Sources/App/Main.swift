import FlightActuator
import FlightCore
import FlightDataPostgres
import FlightTransport
import FlightWeb

/// Your application's module: one place that says what this app is made of.
///
/// `flightRegisterAll` is generated at build time from everything the
/// registration plugin found in this target — every `@Controller`,
/// `@Service`, `@Repository`, and `@Component`. Adding a controller does not
/// mean editing this file.
struct AppModule: FlightModule {
    /// Modules that must be configured before this one. The list is a DAG
    /// resolved once at bootstrap, so ordering is checked rather than hoped
    /// for.
    static var dependencies: [any FlightModule.Type] {
        [PostgresDataModule<PrimaryDataSource>.self]
    }

    func configure(_ container: Container) throws {
        try flightRegisterAll(container)
    }
}

@main
struct Main {
    static func main() async throws {
        // Configuration loads first, then the container is built, the module
        // DAG configures, the container freezes, and only then does the
        // server start accepting requests. Nothing serves traffic against a
        // half-registered container.
        try await Flight.bootstrap(
            configuration: try Configuration.load(),
            modules: [
                FlightWebModule<FlightTransport>.self,
                AppModule.self,
                ActuatorModule.self,
            ]
        )
    }
}
