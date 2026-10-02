import Foundation
import Testing
@testable import SwifterPMCore

struct MirrorsTests {
    @Test
    func packageMirrorsReplaceTheSharedOnesAsAWhole() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let shared = root.appendingPathComponent("shared")
            try await writeMirrors(
                ["https://a.example/A.zip": "https://mirror.example/package/A.zip"],
                to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )
            try await writeMirrors(
                ["https://b.example/B.zip": "https://mirror.example/shared/B.zip"],
                to: shared.appendingPathComponent("mirrors.json")
            )

            let mirrors = try await Environment.$values.withValue([:]) {
                try await MirrorConfig.load(packageDir: package, configPath: shared)
            }

            #expect(mirrors.effectiveLocation(for: "https://a.example/A.zip") == "https://mirror.example/package/A.zip")
            #expect(mirrors.effectiveLocation(for: "https://b.example/B.zip") == "https://b.example/B.zip")
        }
    }

    @Test
    func emptyPackageMirrorsFallBackToTheSharedConfigurationNextToAConfigFile() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let shared = root.appendingPathComponent("shared")
            try await writeMirrors([:], to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json"))
            try await writeMirrors(
                ["https://b.example/B.zip": "https://mirror.example/shared/B.zip"],
                to: shared.appendingPathComponent("mirrors.json")
            )
            let registries = shared.appendingPathComponent("registries.json")
            try await fileSystem.atomicWrite("{}", to: registries)

            let mirrors = try await Environment.$values.withValue([:]) {
                try await MirrorConfig.load(packageDir: package, configPath: registries)
            }

            #expect(mirrors.effectiveLocation(for: "https://b.example/B.zip") == "https://mirror.example/shared/B.zip")
        }
    }

    @Test
    func mirrorConfigEnvironmentVariableReplacesThePackageFileAndHomeIsTheSharedDefault() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let home = root.appendingPathComponent("home")
            let custom = root.appendingPathComponent("custom-mirrors.json")
            try await writeMirrors(
                ["https://a.example/A.zip": "https://mirror.example/package/A.zip"],
                to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )
            try await writeMirrors(
                ["https://c.example/C.zip": "https://mirror.example/custom/C.zip"],
                to: custom
            )
            try await writeMirrors(
                ["https://h.example/H.zip": "https://mirror.example/home/H.zip"],
                to: home.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )

            let customMirrors = try await Environment.$values.withValue([
                "SWIFTPM_MIRROR_CONFIG": custom.path,
                "HOME": home.path,
            ]) {
                try await MirrorConfig.load(packageDir: package, configPath: nil)
            }
            let homeMirrors = try await Environment.$values.withValue([
                "SWIFTPM_MIRROR_CONFIG": root.appendingPathComponent("missing.json").path,
                "HOME": home.path,
            ]) {
                try await MirrorConfig.load(packageDir: package, configPath: nil)
            }

            #expect(customMirrors.effectiveLocation(for: "https://c.example/C.zip") == "https://mirror.example/custom/C.zip")
            #expect(customMirrors.effectiveLocation(for: "https://a.example/A.zip") == "https://a.example/A.zip")
            #expect(homeMirrors.effectiveLocation(for: "https://h.example/H.zip") == "https://mirror.example/home/H.zip")
        }
    }

    @Test
    func relativeMirrorConfigEnvironmentVariableIsRejected() async throws {
        let error = await #expect(throws: (any Error).self) {
            try await Environment.$values.withValue(["SWIFTPM_MIRROR_CONFIG": "mirrors.json"]) {
                try await MirrorConfig.load(packageDir: URL(fileURLWithPath: "/App"), configPath: nil)
            }
        }

        let message = String(describing: try #require(error))
        #expect(message.contains("SWIFTPM_MIRROR_CONFIG must be an absolute path"))
    }

    private func writeMirrors(_ mirrors: [String: String], to path: URL) async throws {
        let object = mirrors.map { ["original": $0.key, "mirror": $0.value] }
        let data = try JSONSerialization.data(withJSONObject: ["object": object, "version": 1])
        try await fileSystem.makeDirectory(
            at: path.deletingLastPathComponent().absolutePath, options: [.createTargetParentDirectories]
        )
        try await fileSystem.atomicWrite(data, to: path)
    }
}
