import Foundation
import Mockable
import Path
import Testing
import TuistConfigLoader
import TuistServer
@testable import TuistSnapshotsCommand

struct SnapshotsTestRunnerTests {
    private let uploadService = MockSnapshotsUploadServicing()

    private actor HashStore {
        var stored = false
        func store() { stored = true }
    }

    /// Runs tests that pass and store their selective-testing hashes the way `TestService` does.
    private func run(storingInto hashStore: HashStore) async throws {
        try await SnapshotsTestRunner(uploadService: uploadService, configLoader: MockConfigLoading()).run(
            enabled: true,
            set: "default",
            path: try AbsolutePath(validating: FileManager.default.temporaryDirectory.path),
            skippedTests: { false },
            tests: { _ in
                let deferrals = try #require(SnapshotsTestRunner.hashStoresAwaitingVerdict)
                await deferrals.append { await hashStore.store() }
            }
        )
    }

    @Test(arguments: ["passed", "baseline", "approved"])
    func storesTheTestHashesOnceTheVerdictPasses(status: String) async throws {
        given(uploadService).upload(directory: .any, options: .any).willReturn(
            ServerSnapshotBuild(id: "build-1", url: "https://tuist.dev/build-1", state: "processed", status: status)
        )
        let hashStore = HashStore()

        try await run(storingInto: hashStore)

        #expect(await hashStore.stored)
    }

    /// A stored hash would make the rerun skip the snapshot target, which then uploads nothing and passes.
    @Test
    func leavesTheTestHashesUnstoredWhileChangesAwaitReview() async throws {
        given(uploadService).upload(directory: .any, options: .any).willThrow(
            SnapshotsUploadServiceError.changesNeedReview(summary: "1 changed", url: "https://tuist.dev/build-1")
        )
        let hashStore = HashStore()

        await #expect(throws: SnapshotsUploadServiceError.self) { try await run(storingInto: hashStore) }

        #expect(await hashStore.stored == false)
    }
}
