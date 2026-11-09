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
    func mirrorConfigurationIsPartOfTheFingerprintOnlyWhenPresent() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let environment = ["HOME": root.appendingPathComponent("home").path]
            try await Environment.$values.withValue(environment) {
                let withoutMirrors = await ManifestEnvironmentFingerprint.current(packageDir: package)
                #expect(withoutMirrors == ManifestEnvironmentFingerprint.current())

                let mirrors = package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
                try await writeMirrorsConfiguration(["acme.dependency": "proxy.dependency"], to: mirrors)
                let first = await ManifestEnvironmentFingerprint.current(packageDir: package)
                try await writeMirrorsConfiguration(["acme.dependency": "proxy.other"], to: mirrors)
                let second = await ManifestEnvironmentFingerprint.current(packageDir: package)

                #expect(first != withoutMirrors)
                #expect(first != second)
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
}
