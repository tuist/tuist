import Foundation
import Testing
@testable import SwifterPMCore

private let packageFixturePaths = [
    "ExternalDependencies",
    "MixedRegistryAndGitHub",
    "SanitizedTuistPackages/Caly-main",
    "SanitizedTuistPackages/Fasting",
    "SanitizedTuistPackages/ProteinTracker",
]

private let manifestOnlyFixturePaths = [
    "EtsyExternalDependencies"
]

struct FixtureResolutionTests {
    @Test(arguments: packageFixturePaths)
    func recordedResolutionCoversManifestDependencies(fixturePath: String) async throws {
        try await withTemporaryDirectory { root in
            let source = try await fixtureURL(fixturePath.split(separator: "/").map(String.init))
            if !(try await installedSwiftSupportsManifest(at: source)) {
                let resolved = try await ResolvedFile.read(packageDir: source)
                #expect(!resolved.pins.isEmpty)
                return
            }

            let package = root.appendingPathComponent(source.lastPathComponent)
            try await SystemProcess.run("/bin/cp", ["-R", source.path, package.path])

            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: package, disableSandbox: true)
            let dependencies = try ManifestParser.dependencies(manifest)
            let resolved = try await ResolvedFile.read(packageDir: package)
            let pinsByIdentity = Dictionary(
                uniqueKeysWithValues: resolved.pins.map { ($0.identity.lowercased(), $0) })

            #expect(!dependencies.isEmpty)
            #expect(!resolved.pins.isEmpty)

            for dependency in dependencies {
                let pin = pinsByIdentity[dependency.identity.lowercased()]
                #expect(pin != nil)
                guard let pin else { continue }

                switch dependency.requirement {
                case .exact(let version):
                    #expect(pin.state.version == version.description)
                case .revision(let revision):
                    #expect(pin.state.revision == revision)
                case .branch(let branch):
                    #expect(pin.state.branch == branch)
                case .range:
                    break
                }
            }
        }
    }

    @Test(arguments: manifestOnlyFixturePaths)
    func manifestOnlyFixturesDumpAndParseDependencies(fixturePath: String) async throws {
        try await withTemporaryDirectory { root in
            let source = try await fixtureURL(fixturePath.split(separator: "/").map(String.init))
            let package = root.appendingPathComponent(source.lastPathComponent)
            try await SystemProcess.run("/bin/cp", ["-R", source.path, package.path])

            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: package, disableSandbox: true)
            let dependencies = try ManifestParser.dependencies(manifest)
            let dependenciesByIdentity = Dictionary(
                uniqueKeysWithValues: dependencies.map { ($0.identity.lowercased(), $0) })

            #expect(dependencies.count == 40)
            #expect(
                exactVersion("googlesignin-ios", in: dependenciesByIdentity) == "8.0.0")
            #expect(exactVersion("swift-nio", in: dependenciesByIdentity) == "2.97.0")
            #expect(
                exactVersion("sierra-ios-sdk", in: dependenciesByIdentity)
                    == "0.20260515.7173715")
            #expect(
                revision("panmodal", in: dependenciesByIdentity)
                    == "2322ef9cec54127b7ae69bbed01f8b598e35aca4")
            #expect(revision("ios-secrets-prod", in: dependenciesByIdentity) == "9a089f5")
        }
    }

    private func exactVersion(
        _ identity: String,
        in dependencies: [String: ManifestDependency]
    ) -> String? {
        guard let dependency = dependencies[identity] else { return nil }
        guard case .exact(let version) = dependency.requirement else { return nil }
        return version.description
    }

    private func revision(
        _ identity: String,
        in dependencies: [String: ManifestDependency]
    ) -> String? {
        guard let dependency = dependencies[identity] else { return nil }
        guard case .revision(let revision) = dependency.requirement else { return nil }
        return revision
    }
}
