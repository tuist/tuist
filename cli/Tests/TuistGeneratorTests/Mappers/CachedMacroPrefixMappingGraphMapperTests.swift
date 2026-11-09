import Foundation
import Mockable
import Path
import TestCoverageAttribution
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

@Suite(.coverageAttribution)
struct CachedMacroPrefixMappingGraphMapperTests {
    private let cached =
        try! AbsolutePath(validating: "/Users/a/.cache/tuist/Binaries/3f9c/Stringify.macro") // swiftlint:disable:this force_try
    private let projectPath = try! AbsolutePath(validating: "/project") // swiftlint:disable:this force_try

    private func environment() -> MapperEnvironment {
        var environment = MapperEnvironment()
        environment.cachedMacroHashes = [cached: "binary-cache-hash"]
        return environment
    }

    @Test(.withMockedXcodeController)
    func map_loadsCachedMacrosThroughToolchainFlagsAndMapsThemInEveryProject() async throws {
        // Given
        given(try #require(XcodeController.mocked)).selectedVersion().willReturn(Version(27, 0, 0))
        let vendored = try AbsolutePath(validating: "/project/Vendor/Vendored.macro")
        let consumer = Target.test(
            name: "Consumer",
            settings: Settings.default.with(base: ["OTHER_SWIFT_FLAGS": "-DFOO"])
        )
        let bare = Target.test(name: "Bare", settings: nil)
        let unrelated = Target.test(name: "Unrelated", settings: nil)
        let project = Project.test(
            path: projectPath,
            settings: Settings(
                base: ["SWIFT_OTHER_PREFIX_MAPPINGS": .array(["$(inherited)", "\"/root=/^root\""])],
                configurations: Settings.default.configurations,
                defaultSettings: .essential()
            ),
            targets: [consumer, bare, unrelated]
        )
        let other = Project.test(
            path: try AbsolutePath(validating: "/other"),
            settings: Settings(base: [:], configurations: [:]),
            targets: []
        )
        let graph = Graph.test(projects: [project.path: project, other.path: other], dependencies: [
            .target(name: consumer.name, path: project.path): [.macro(path: cached), .macro(path: vendored)],
            .target(name: bare.name, path: project.path): [.target(name: consumer.name, path: project.path)],
            .target(name: unrelated.name, path: project.path): [],
        ])

        // When
        let (mapped, _, _) = try await CachedMacroPrefixMappingGraphMapper(compilationCachingEnabled: true)
            .map(graph: graph, environment: environment())

        // Then
        let mapping = "\"/Users/a/.cache/tuist/Binaries/3f9c=/^macro-binary-cache-hash\""
        let driverFlags = ["-load-plugin-executable", "\"\(cached.pathString)#Stringify\""]
        let mappedProject = try #require(mapped.projects[project.path])
        #expect(mappedProject.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == .array([
            "$(inherited)", "\"/root=/^root\"", mapping,
        ]))
        #expect(mapped.projects[other.path]?.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == .array(["$(inherited)", mapping]))
        let consumerBase = try #require(mappedProject.targets[consumer.name]?.settings?.base)
        #expect(consumerBase["OTHER_SWIFT_FLAGS"] == "-DFOO")
        #expect(consumerBase["SWIFT_TOOLCHAIN_FLAGS"] == .array(["$(inherited)"] + driverFlags))
        let bareSettings = try #require(mappedProject.targets[bare.name]?.settings)
        #expect(bareSettings.base["SWIFT_TOOLCHAIN_FLAGS"] == .array(["$(inherited)"] + driverFlags))
        #expect(bareSettings.configurations.isEmpty)
        #expect(bareSettings.defaultSettings == .essential())
        #expect(mappedProject.targets[unrelated.name]?.settings == nil)
    }

    @Test(.withMockedXcodeController, arguments: [(true, Version(26, 4, 0)), (false, Version(27, 0, 0))])
    func map_leavesTheGraphUntouched_withoutCompilationCachingPrefixMapping(
        compilationCachingEnabled: Bool,
        xcodeVersion: Version
    ) async throws {
        given(try #require(XcodeController.mocked)).selectedVersion().willReturn(xcodeVersion)
        let consumer = Target.test(name: "Consumer", settings: nil)
        let project = Project.test(path: projectPath, targets: [consumer])
        let graph = Graph.test(projects: [project.path: project], dependencies: [
            .target(name: consumer.name, path: project.path): [.macro(path: cached)],
        ])

        let (mapped, _, _) = try await CachedMacroPrefixMappingGraphMapper(
            compilationCachingEnabled: compilationCachingEnabled
        ).map(graph: graph, environment: environment())

        #expect(mapped == graph)
    }
}
