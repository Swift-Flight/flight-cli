import FlightActuator
import FlightCore
import FlightDataPostgres
import FlightTransport
import FlightWeb
import Foundation

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

        // `@Repository` registers the concrete type — `UserRepository` — and
        // only that. Controllers depend on `UserRepositoryProtocol` instead,
        // which is the whole point of the seam (see UserRepositoryProtocol.swift),
        // so the binding from protocol to implementation is stated here.
        // Without it the routes compile and the tests pass — the suite
        // registers its own fake against the same protocol — and every
        // request fails at runtime with "No component registered".
        //
        // `.scoped` matches the repository's own lifetime: one instance per
        // request, holding that request's connection.
        container.register((any UserRepositoryProtocol).self, scope: .scoped) { c in
            try UserRepository(_flight: c)
        }
    }
}

@main
struct Main {
    static func main() async {
        // Configuration loads first, then the container is built, the module
        // DAG configures, the container freezes, and only then does the
        // server start accepting requests. Nothing serves traffic against a
        // half-registered container.
        do {
            try await Flight.bootstrap(
                configuration: try Configuration.load(),
                modules: [
                    FlightWebModule<FlightTransport>.self,
                    AppModule.self,
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
