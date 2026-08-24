import FlightMigrate
import FlightMigrateCLI
import Migrations

@main
struct Migrate: MigrateTool {
    static var migrations: [MigrationEntry] { _allMigrations() }
}