import Foundation
import Path
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
    func currentUsesScopedManifestEnvironment() async throws {
        try await Environment.$values.withValue([
            "BENCH_NONCE": "first",
            "RETAINED": "value",
        ]) {
            try await Environment.withManifestEnvironment(["RETAINED": "value"]) {
                #expect(
                    ManifestEnvironmentFingerprint.current()
                        == ManifestEnvironmentFingerprint.digest(for: ["RETAINED": "value"])
                )
            }
        }
    }

    @Test
    func digestDistinguishesEmbeddedNewlinesFromSeparateEntries() {
        // A value containing the delimiter must not collide with two distinct entries.
        let withNewline = ManifestEnvironmentFingerprint.digest(for: ["A": "x\nB=y"])
        let split = ManifestEnvironmentFingerprint.digest(for: ["A": "x", "B": "y"])

        #expect(withNewline != split)
    }

    @Test
    func sidecarPathAppendsEnvhashExtension() throws {
        let cache = try AbsolutePath(
            validating: "/tmp/Package/.build/swifterpm/manifests/package.json")

        #expect(
            ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache).pathString
                == "/tmp/Package/.build/swifterpm/manifests/package.json.envhash")
    }

    @Test
    func validateReturnsMissingWhenNoSidecarExists() async throws {
        try await withTemporaryDirectory { root in
            let cache = try root.appendingPathComponent("package.json").absolutePath
            try await fileSystem.write(Data("{}".utf8), to: cache)

            let validation = try await ManifestEnvironmentFingerprint.validate(forCacheFile: cache)

            #expect(validation == .missing)
        }
    }

    @Test
    func validateReturnsMatchingWhenSidecarMatchesCurrentEnvironment() async throws {
        try await withTemporaryDirectory { root in
            let cache = try root.appendingPathComponent("package.json").absolutePath
            try await fileSystem.write(Data("{}".utf8), to: cache)
            try await ManifestEnvironmentFingerprint.write(forCacheFile: cache)

            let validation = try await ManifestEnvironmentFingerprint.validate(forCacheFile: cache)

            #expect(validation == .matching)
        }
    }

    @Test
    func validateReturnsMismatchingWhenSidecarDiffersFromCurrentEnvironment() async throws {
        try await withTemporaryDirectory { root in
            let cache = try root.appendingPathComponent("package.json").absolutePath
            try await fileSystem.write(Data("{}".utf8), to: cache)
            try await fileSystem.write(
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
            let cache = try root.appendingPathComponent("package.json").absolutePath

            try await ManifestEnvironmentFingerprint.write(forCacheFile: cache)

            let stored = String(
                data: try await fileSystem.readFile(
                    at: ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache)),
                encoding: .utf8
            )
            #expect(stored == ManifestEnvironmentFingerprint.current())
        }
    }
}
