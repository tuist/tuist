import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import TuistServer

struct ExecutablePreviewManifestTests {
    @Test(.inTemporaryDirectory)
    func detectsArtifactTargetRatherThanUploadHost() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let executable = directory.appending(component: "tool").url
        var elf = [UInt8](repeating: 0, count: 64)
        elf.replaceSubrange(0 ..< 6, with: [0x7F, 0x45, 0x4C, 0x46, 2, 1])
        elf[18] = 62
        try Data(elf).write(to: executable)
        #expect(try ExecutablePreviewTarget.read(at: executable) == .init(platform: "linux", architectures: ["x86_64"]))
        elf[18] = 183
        try Data(elf).write(to: executable)
        #expect(try ExecutablePreviewTarget.read(at: executable) == .init(platform: "linux", architectures: ["arm64"]))

        var universal: [UInt8] = [
            0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2,
            1, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 16, 0, 0, 0, 0,
            1, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 16, 0, 0, 0, 0,
        ]
        try Data(universal).write(to: executable)
        #expect(try ExecutablePreviewTarget.read(at: executable) == .init(platform: "macos", architectures: ["arm64", "x86_64"]))

        universal[31] = 7
        try Data(universal).write(to: executable)
        #expect(try ExecutablePreviewTarget.read(at: executable) == .init(platform: "macos", architectures: ["x86_64"]))

        universal[28] = 0
        try Data(universal).write(to: executable)
        #expect(try ExecutablePreviewTarget.read(at: executable) == .init(platform: "macos", architectures: ["x86_64"]))

        try Data(universal.prefix(28)).write(to: executable)
        #expect(throws: (any Error).self) { try ExecutablePreviewTarget.read(at: executable) }

        try Data("not an executable".utf8).write(to: executable)
        #expect(throws: (any Error).self) { try ExecutablePreviewTarget.read(at: executable) }
    }
}
