import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistConfig
import TuistCore
import TuistGenerator
import TuistHasher
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistKit

/// The binary-cache keys a project gets with coverage off must stay those of releases without the option, so
/// turning the option on is the only thing that invalidates a warm cache.
struct BinaryCacheCoverageHashTests {
    private let repositoryPath = try! AbsolutePath(validating: "/repo")
    private let packagePath = try! AbsolutePath(validating: "/repo/Tuist/.build/checkouts/Package")

    private var graph: Graph {
        let settings = Settings(
            base: ["SWIFT_VERSION": "5"],
            configurations: [.debug("Debug"): nil, .release("Release"): nil]
        )
        let repository = Project.test(
            path: repositoryPath,
            settings: settings,
            targets: [.test(
                name: "Core",
                destinations: [.iPhone],
                product: .staticFramework,
                bundleId: "dev.tuist.Core",
                settings: nil
            )]
        )
        let package = Project.test(
            path: packagePath,
            settings: settings,
            targets: [.test(
                name: "Package",
                destinations: [.iPhone],
                product: .staticFramework,
                bundleId: "dev.tuist.Package",
                settings: nil
            )],
            type: .external(hash: "revision")
        )
        return Graph.test(path: repositoryPath, projects: [repositoryPath: repository, packagePath: package])
    }

    /// The graph as the generator hands it to the hasher: the projects mapped by the coverage-aware project mappers.
    private func hashes(
        coverage: BinaryCacheCoverage,
        prefixMapping: Bool = false,
        configuration: String = "Debug"
    ) async throws -> [String: String] {
        let config = Tuist.test(
            project: .generated(.test(generationOptions: .test(
                enableCaching: true,
                coverage: .init(prefixMapping: prefixMapping)
            )))
        ).resolvingCoverage(coverage)
        var graph = graph
        for (path, project) in graph.projects {
            var project = project
            for mapper in [
                CoverageLinkerSettingsProjectMapper(enabled: coverage == .on) as ProjectMapping,
                XcodeCacheSettingsProjectMapper(tuist: config),
            ] {
                project = try await mapper.map(project: project).0
            }
            graph.projects[path] = project
        }
        let hashes = try await CacheGraphContentHasher(contentHasher: ContentHasher()).contentHashes(
            for: graph,
            configuration: configuration,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil,
            coverage: coverage
        )
        return Dictionary(uniqueKeysWithValues: hashes.map { ($0.key.target.name, $0.value.hash) })
    }

    private func stub(xcodeVersion: Int = 26) throws {
        given(try #require(SwiftVersionProvider.mocked)).swiftlangVersion().willReturn("6.2.0.1.1")
        given(try #require(XcodeController.mocked)).selectedBuildVersion().willReturn("17A324")
        given(try #require(XcodeController.mocked)).selectedVersion().willReturn(.init(xcodeVersion, 0, 0))
    }

    /// Recorded with coverage off; a change here means every customer's binary cache misses after upgrading.
    @Test(.withMockedEnvironment(), .withMockedSwiftVersionProvider, .withMockedXcodeController)
    func coverageOff_keepsTheKeysOfReleasesWithoutTheOption() async throws {
        try stub()

        let got = try await hashes(coverage: .off)

        #expect(got == [
            "Core": "ceafb5423020ce457a5efed57bd038cc",
            "Package": "e3b181a20f9b2385ff59a132981b2d4a",
        ])
    }

    @Test(.withMockedEnvironment(), .withMockedSwiftVersionProvider, .withMockedXcodeController)
    func coverageOn_changesOnlyTheRepositoryKeysOfDebugConfigurations() async throws {
        try stub()

        let off = try await hashes(coverage: .off)
        let on = try await hashes(coverage: .on)
        let releaseOff = try await hashes(coverage: .off, configuration: "Release")
        let releaseOn = try await hashes(coverage: .on, configuration: "Release")

        #expect(on["Core"] != off["Core"])
        #expect(on["Package"] == off["Package"])
        #expect(releaseOn == releaseOff)
    }

    @Test(.withMockedEnvironment(), .withMockedSwiftVersionProvider, .withMockedXcodeController, arguments: [26, 27])
    func prefixMapping_changesKeysOnlyWhenOnWithXcode27(xcodeVersion: Int) async throws {
        try stub(xcodeVersion: xcodeVersion)

        let off = try await hashes(coverage: .off)
        let mapped = try await hashes(coverage: .off, prefixMapping: true)

        #expect(xcodeVersion >= 27 ? mapped != off : mapped == off)
    }
}
