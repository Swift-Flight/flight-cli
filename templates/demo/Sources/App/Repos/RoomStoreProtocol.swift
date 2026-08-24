import Foundation

/// The narrow slice of `ChatRepository` that `RoomChannel` actually needs.
///
/// Same reasoning as `UserRepositoryProtocol`, applied to the real-time path:
/// a struct wrapping a live database scope cannot be swapped out, a protocol
/// can. Depending on this instead of the concrete repository is what lets the
/// channel's join gate, its persist-before-broadcast ordering, and its
/// presence tracking be tested without a database anywhere in the loop.
///
/// It is deliberately three methods rather than all of `ChatRepository`. The
/// channel does not read history, run aggregates, or archive rooms, and a
/// seam that exposes more than its consumer uses is a seam that is expensive
/// to fake and easy to widen by accident.
///
/// `ChatRepository` conforms for free below — its signatures already match.
protocol RoomStore: Sendable {
    func room(slug: String, messageLimit: Int) async throws -> Room?
    func authorIDs(forNames names: [String]) async throws -> [String: UUID]
    func post(_ messages: [ChatMessage]) async throws -> [ChatMessage]
}

// The conformance itself lives in ChatRepository.swift: a protocol refining
// Sendable can only be conformed to in the type's own file.
