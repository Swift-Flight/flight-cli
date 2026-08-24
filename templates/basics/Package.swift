// swift-tools-version: 6.2
import PackageDescription

// A Flight application with a database: everything the skeleton has, plus
// entities, migrations, a repository, and CRUD routes over Postgres.
//
// `flight-data` arrives with `traits: ["Postgres"]`. Traits are how a package
// carries drivers without imposing them: without that trait, PostgresNIO is
// not merely unused, it is never resolved. Add "Valkey" alongside it when you
// want the cache and data-source adapters for that too.
let package = Package(
    name: "App",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "App", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/Swift-Flight/flight.git", from: "0.1.0"),
        .package(url: "https://github.com/Swift-Flight/flight-data.git", from: "0.1.0", traits: ["Postgres"]),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "FlightCore", package: "flight"),
                .product(name: "FlightWeb", package: "flight"),
                .product(name: "FlightTransport", package: "flight"),
                .product(name: "FlightActuator", package: "flight"),
                .product(name: "FlightDataPostgres", package: "flight-data"),
            ],
            plugins: [
                .plugin(name: "FlightRegistrationPlugin", package: "flight")
            ]
        ),

        // Migrations live in their own target so the migrate plugin can scan
        // them and generate the `_allMigrations()` registry at build time.
        // The app target deliberately does NOT depend on this: migrations are
        // something you run, not something your server does at boot.
        .target(
            name: "Migrations",
            dependencies: [.product(name: "FlightMigrate", package: "flight-data")],
            plugins: [.plugin(name: "FlightMigratePlugin", package: "flight-data")]
        ),

        // `swift run migrate status | up | down | create`.
        .executableTarget(
            name: "migrate",
            dependencies: [
                "Migrations",
                .product(name: "FlightMigrateCLI", package: "flight-data"),
            ]
        ),

        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                .product(name: "FlightCore", package: "flight"),
                .product(name: "FlightWeb", package: "flight"),
                .product(name: "FlightWebTesting", package: "flight"),
                .product(name: "FlightDataPostgres", package: "flight-data"),
            ]
        ),
    ]
)
