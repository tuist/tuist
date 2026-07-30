import Foundation
import Testing
@testable import SwifterPMCore

struct ManifestEnvironmentFingerprintTests {
    @Test
    func digestIsStableAcrossDictionaryOrdering() {
        let first = ManifestEnvironmentFingerprint.digest(for: ["A": "1", "B": "2"])
        let second = ManifestEnvironmentFingerprint.digest(for: ["B": "2", "A": "1"])

        #expect(first == second)
    }

    @Test
    func digestDiffersWhenValuesChange() {
        let first = ManifestEnvironmentFingerprint.digest(for: ["REPRO_USE_ALTERNATE": "1"])
        let second = ManifestEnvironmentFingerprint.digest(for: ["REPRO_USE_ALTERNATE": "0"])

        #expect(first != second)
    }

    @Test
    func sidecarPathAppendsEnvhashExtension() {
        let cache = URL(fileURLWithPath: "/tmp/Package/.build/swifterpm/manifests/package.json")

        #expect(
            ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache).path
                == "/tmp/Package/.build/swifterpm/manifests/package.json.envhash")
    }

    @Test
    func validateReturnsMissingWhenNoSidecarExists() async throws {
        try await withTemporaryDirectory { root in
            let cache = root.appendingPathComponent("package.json")
            try await fileSystem.atomicWrite(Data("{}".utf8), to: cache)

            let validation = try await ManifestEnvironmentFingerprint.validate(forCacheFile: cache)

            #expect(validation == .missing)
        }
    }

    @Test
    func validateReturnsMatchingWhenSidecarMatchesCurrentEnvironment() async throws {
        try await withTemporaryDirectory { root in
            let cache = root.appendingPathComponent("package.json")
            try await fileSystem.atomicWrite(Data("{}".utf8), to: cache)
            try await ManifestEnvironmentFingerprint.write(forCacheFile: cache)

            let validation = try await ManifestEnvironmentFingerprint.validate(forCacheFile: cache)

            #expect(validation == .matching)
        }
    }

    @Test
    func validateReturnsMismatchingWhenSidecarDiffersFromCurrentEnvironment() async throws {
        try await withTemporaryDirectory { root in
            let cache = root.appendingPathComponent("package.json")
            try await fileSystem.atomicWrite(Data("{}".utf8), to: cache)
            try await fileSystem.atomicWrite(
                Data("a-fingerprint-produced-under-a-different-environment".utf8),
                to: ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache)
            )

            let validation = try await ManifestEnvironmentFingerprint.validate(forCacheFile: cache)

            #expect(validation == .mismatching)
        }
    }

    @Test
    func writeRecordsCurrentEnvironmentFingerprint() async throws {
        try await withTemporaryDirectory { root in
            let cache = root.appendingPathComponent("package.json")

            try await ManifestEnvironmentFingerprint.write(forCacheFile: cache)

            let stored = String(
                data: try await fileSystem.readFile(
                    at: ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache).absolutePath),
                encoding: .utf8
            )
            #expect(stored == ManifestEnvironmentFingerprint.current())
        }
    }
}
