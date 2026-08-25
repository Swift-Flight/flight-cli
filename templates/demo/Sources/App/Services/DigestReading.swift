import Foundation

/// The two digest reads a scheduled job needs, as a seam.
///
/// Same reason as `RoomStore` and `DigestInvalidating`: `RoomDigestService`
/// carries a live cache and a gateway that needs a database, so a job
/// depending on it concretely could not be tested without both. Depending on
/// three method signatures instead means `ChatJobs` is testable by
/// constructing it — no container, no scheduler, no Postgres.
protocol DigestReading: Sendable {
    func activity(minimumMessages: Int) async throws -> [RoomActivity]
    func headlines() async throws -> [RoomHeadline]
}
