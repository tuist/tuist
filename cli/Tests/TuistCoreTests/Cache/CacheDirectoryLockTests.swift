import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore

struct CacheDirectoryLockTests {
    /// Commands that use a cache have to keep running concurrently with each other, so shared
    /// access must not serialize them. Each task waits for the other to be inside its own critical
    /// section before leaving, which cannot complete unless both are inside at once.
    @Test(.inTemporaryDirectory) func shared_access_admits_other_shared_access() async throws {
        // Given
        let subject = CacheDirectoryLock(cacheDirectory: try #require(FileSystem.temporaryTestDirectory))
        let first = Signal()
        let second = Signal()

        // When / Then
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await subject.whileUsing(.manifests) {
                    first.send()
                    await second.wait()
                }
            }
            group.addTask {
                try await subject.whileUsing(.manifests) {
                    second.send()
                    await first.wait()
                }
            }
            try await group.waitForAll()
        }
    }

    /// A clean has to see a cache nobody else is touching, so nothing may enter while it holds the
    /// directory. The assertion is that the waiting task has not run, which a slow machine can only
    /// make more true, so there is no timing window in which this passes spuriously.
    @Test(.inTemporaryDirectory) func exclusive_access_keeps_other_access_out() async throws {
        // Given
        let subject = CacheDirectoryLock(cacheDirectory: try #require(FileSystem.temporaryTestDirectory))
        let holding = Signal()
        let entered = Signal()

        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await subject.whileEmptying(.manifests) {
                    holding.send()
                    // Then: the other task cannot be inside while this one holds the directory.
                    #expect(await entered.hasFired(within: .milliseconds(200)) == false)
                }
            }
            group.addTask {
                await holding.wait()
                try await subject.whileUsing(.manifests) {
                    entered.send()
                }
            }
            try await group.waitForAll()
        }

        // Then: and it gets in once the directory is released.
        #expect(await entered.hasFired(within: .seconds(5)))
    }
}

/// A one-shot latch. `Signal` rather than a continuation pair so that a second `send` is harmless,
/// which keeps a failing expectation from hanging the task group it is checked in.
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func send() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    var isFired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }

    func wait() async {
        while !isFired {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func hasFired(within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: duration)
        while ContinuousClock.now < deadline {
            if isFired { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return isFired
    }
}
