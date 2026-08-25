import FlightCache
import FlightCore
import Foundation

/// The read-heavy side of the chat app, cached.
///
/// `activity` and `headlines` are the two genuinely expensive queries in this
/// demo — a GROUP BY … HAVING over every message, and a DISTINCT ON across
/// every room. They are also the two most likely to be polled by a dashboard
/// on a timer, which is exactly the shape a cache is for: expensive to
/// compute, cheap to reuse, tolerant of being a few seconds stale.
///
/// `@Cacheable` expands **into the method body** rather than wrapping the type
/// in a proxy. That is the difference that matters versus Spring's version:
/// a call from one method of this type to another still goes through the
/// cache, because there is no proxy to bypass. The Spring footgun cannot
/// occur here.
///
/// The cache is coalescing: if fifty requests miss the same key at once, one
/// of them computes and the other forty-nine wait for that result instead of
/// stampeding the database.
/// Registered by hand in `AppModule` rather than scanned, because its
/// dependency is the gateway rather than a component the container can wire
/// on its own.
struct RoomDigestService: DigestInvalidating, DigestReading {
    let chat: ChatGateway

    /// Cached per `minimumMessages` — the argument is part of the key, so
    /// `?min=3` and `?min=10` are different entries rather than one poisoning
    /// the other.
    @Cacheable(namespace: "room-digest", ttl: .seconds(30))
    func activity(minimumMessages: Int) async throws -> [RoomActivity] {
        try await chat.activity(minimumMessages: minimumMessages)
    }

    @Cacheable(namespace: "room-digest", ttl: .seconds(30))
    func headlines() async throws -> [RoomHeadline] {
        try await chat.headlines()
    }

    /// Called whenever a message lands, from either the REST or the WebSocket
    /// path. Both digests are derived from the message table, so a new message
    /// invalidates the whole namespace rather than trying to work out which
    /// `minimumMessages` buckets a single row could have moved.
    ///
    /// A 30-second TTL would eventually do this on its own. Evicting on write
    /// is what makes "post a message, reload the dashboard, see it" true
    /// immediately — the property a user would otherwise report as a bug.
    @CacheEvict(namespace: "room-digest", allEntries: true)
    func messagesChanged() async {}
}
