import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistSupport

struct VolumeSpaceTests {
    @Test(.inTemporaryDirectory)
    func readReportsTheVolumeBackingAnExistingDirectory() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)

        let space = try #require(VolumeSpace.read(at: directory))

        #expect(space.totalBytes > 0)
        #expect(space.freeBytes >= 0)
        #expect(space.freeBytes <= space.totalBytes)
    }

    @Test(.inTemporaryDirectory)
    func readWalksUpToTheNearestExistingAncestor() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        // A build that failed on a full volume may never have created the directory it was writing into,
        // and the volume it would have landed on is exactly what we need to report.
        let neverCreated = directory.appending(components: ["Build", "Products", "Debug"])

        let space = try #require(VolumeSpace.read(at: neverCreated))

        #expect(space == VolumeSpace.read(at: directory))
    }

    @Test func isExhaustedTracksTheThreshold() {
        let total: Int64 = 100 * 1024 * 1024 * 1024

        #expect(VolumeSpace(freeBytes: 16 * 1024 * 1024, totalBytes: total).isExhausted)
        #expect(!VolumeSpace(freeBytes: 40 * 1024 * 1024 * 1024, totalBytes: total).isExhausted)
    }

    @Test func formattedFreeSpaceNamesBothNumbers() {
        let space = VolumeSpace(freeBytes: 500 * 1024 * 1024, totalBytes: 100 * 1024 * 1024 * 1024)

        #expect(space.formattedFreeSpace.contains("free of"))
    }
}
