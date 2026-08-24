import Foundation
import Synchronization

@testable import App

/// An in-memory `RoomStore`, so the real-time suite exercises the real
/// Channels/PubSub/Presence stack with no database anywhere in it.
///
/// It records what was written, which is how the tests assert the property
/// that matters most in `RoomChannel`: the message is persisted *before* it is
/// broadcast, never the other way round.
final class FakeRoomStore: RoomStore, Sendable {
    struct State {
        var rooms: [String: Room] = [:]
        var authors: [String: UUID] = [:]
        var posted: [ChatMessage] = []
        /// Set to make `post` fail, so the broadcast-on-failure path can be
        /// tested rather than assumed.
        var postFails = false
    }

    private let state = Mutex(State())

    init(rooms: [Room] = [], authors: [String: UUID] = [:]) {
        state.withLock {
            $0.rooms = Dictionary(uniqueKeysWithValues: rooms.map { ($0.slug, $0) })
            $0.authors = authors
        }
    }

    var posted: [ChatMessage] { state.withLock { $0.posted } }

    func failPosts() { state.withLock { $0.postFails = true } }

    // MARK: RoomStore

    func room(slug: String, messageLimit: Int) async throws -> Room? {
        state.withLock { $0.rooms[slug] }
    }

    func authorIDs(forNames names: [String]) async throws -> [String: UUID] {
        state.withLock { store in
            store.authors.filter { names.contains($0.key) }
        }
    }

    func post(_ messages: [ChatMessage]) async throws -> [ChatMessage] {
        try state.withLock { store in
            if store.postFails { throw FakeError.postRefused }
            store.posted.append(contentsOf: messages)
            return messages
        }
    }

    enum FakeError: Error { case postRefused }
}

extension Room {
    /// A room with the fields the real-time path reads; the rest is filler.
    static func fixture(slug: String, name: String? = nil, archived: Bool = false) -> Room {
        Room(
            id: UUID(), slug: slug, name: name ?? slug.capitalized,
            archived: archived, createdAt: Date())
    }
}
