import Foundation
import OpenSnekCore

/// Coordinates apply coordinator behavior.
public final class ApplyCoordinator: @unchecked Sendable {
    /// Stores apply coordinator entry data.
    public struct Entry {
        public let patch: DevicePatch
        public let generation: UInt64

        public init(patch: DevicePatch, generation: UInt64) {
            self.patch = patch
            self.generation = generation
        }
    }

    private var pendingEntry: Entry?
    public private(set) var stateRevision: UInt64 = 0

    public init() {}

    @discardableResult
    public func enqueue(_ patch: DevicePatch) -> Bool {
        enqueue(patch, generation: 0)
    }

    @discardableResult
    public func enqueue(_ patch: DevicePatch, generation: UInt64) -> Bool {
        if let pendingEntry, pendingEntry.generation == generation {
            self.pendingEntry = Entry(
                patch: pendingEntry.patch.merged(with: patch),
                generation: generation
            )
        } else {
            pendingEntry = Entry(patch: patch, generation: generation)
        }
        stateRevision &+= 1
        return true
    }

    public func dequeue() -> DevicePatch? {
        dequeueEntry()?.patch
    }

    public func dequeueEntry() -> Entry? {
        let entry = pendingEntry
        pendingEntry = nil
        return entry
    }

    public var hasPending: Bool {
        pendingEntry != nil
    }

    public func clearPending() {
        pendingEntry = nil
        stateRevision &+= 1
    }

    public func bumpRevision() {
        stateRevision &+= 1
    }
}
