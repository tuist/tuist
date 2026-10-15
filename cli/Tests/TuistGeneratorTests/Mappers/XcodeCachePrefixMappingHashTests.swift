import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistConfig
import TuistConstants
import TuistCore
import TuistHasher
import TuistRootDirectoryLocator
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct XcodeCachePrefixMappingHashTests {
    private func hash(
        project: Project,
        root: AbsolutePath,
        enableCaching: Bool,
        enableCachingPrefixMapping: Bool,
        casPluginPath: AbsolutePath? = nil
    ) async throws -> String {
        let tuist = Tuist(
            project: .generated(.test(generationOptions: .test(
                enableCaching: enableCaching,
                enableCachingPrefixMapping: enableCachingPrefixMapping
            ))),
            fullHandle: casPluginPath == nil ? nil : "test/project",
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let (mappedProject, _) = try await XcodeCacheSettingsProjectMapper(
            tuist: tuist,
            casPluginCandidates: casPluginPath.map { [$0] } ?? []
        ).map(project: project)
        let locator = MockRootDirectoryLocating()
        given(locator).locate(from: .any).willReturn(root)
        let (mappedWorkspace, _) = try await XcodeCachePrefixMappingWorkspaceMapper(
            tuist: tuist,
            rootDirectoryLocator: locator
        ).map(workspace: WorkspaceWithProjects(
            workspace: .test(path: root),
            projects: [mappedProject]
        ))
        let contentHasher = MockContentHashing()
        given(contentHasher).hash(Parameter<String>.any).willProduce { $0 }
        given(contentHasher).hash(Parameter<[String]>.any).willProduce { $0.joined(separator: ";") }
        let hasher = SettingsContentHasher(contentHasher: contentHasher, xcconfigHasher: MockXCConfigContentHashing())
        let mapped = try #require(mappedWorkspace.projects.first)
        var hashes = [try await hasher.hash(settings: mapped.settings)]
        for target in mapped.targets.values.sorted(by: { $0.name < $1.name }) {
            if let settings = target.settings {
                hashes.append(try await hasher.hash(settings: settings))
            }
        }
        return hashes.joined(separator: ";")
    }

    @Test(.withMockedXcodeController, arguments: [false, true])
    func hash_withPrefixMappingOptOut_matchesCachingDisabled(onXcode27: Bool) async throws {
        let controller = try #require(XcodeController.mocked)
        given(controller).selectedVersion().willReturn(Version(onXcode27 ? 27 : 26, 0, 0))
        let root = try AbsolutePath(validating: "/repo")
        let project = Project.test(
            path: root,
            settings: .test(base: ["SWIFT_VERSION": "5"]),
            swiftPackageManagerScratchDirectory: root.appending(components: "Tuist", ".build")
        )

        let cached = try await hash(project: project, root: root, enableCaching: true, enableCachingPrefixMapping: false)
        let uncached = try await hash(project: project, root: root, enableCaching: false, enableCachingPrefixMapping: false)
        let existingUncached = try await hash(
            project: project,
            root: root,
            enableCaching: false,
            enableCachingPrefixMapping: true
        )

        #expect(cached == uncached)
        #expect(uncached == existingUncached)
        let defaultCached = try await hash(project: project, root: root, enableCaching: true, enableCachingPrefixMapping: true)
        #expect(onXcode27 ? defaultCached != cached : defaultCached == cached)
    }

    @Test(.withMockedXcodeController)
    func hash_withPrefixMappingOptOut_stillHashesUserMappings() async throws {
        let controller = try #require(XcodeController.mocked)
        given(controller).selectedVersion().willReturn(Version(27, 0, 0))
        let root = try AbsolutePath(validating: "/repo")
        let first = Project.test(settings: .test(base: [
            "SWIFT_OTHER_PREFIX_MAPPINGS": .array(["/repo=/^first"]),
        ]))
        let second = Project.test(settings: .test(base: [
            "SWIFT_OTHER_PREFIX_MAPPINGS": .array(["/repo=/^second"]),
        ]))

        let firstHash = try await hash(project: first, root: root, enableCaching: true, enableCachingPrefixMapping: false)
        let secondHash = try await hash(project: second, root: root, enableCaching: true, enableCachingPrefixMapping: false)

        #expect(firstHash != secondHash)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController, arguments: [false, true])
    func hash_withPrefixMappingOptOut_preservesLegacyRemoteFlagNormalization(atTargetLevel: Bool) async throws {
        let controller = try #require(XcodeController.mocked)
        given(controller).selectedVersion().willReturn(Version(27, 0, 0))
        let root = try #require(FileSystem.temporaryTestDirectory)
        let plugin = root.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().writeText("plugin", at: plugin)
        let project = atTargetLevel ? Project.test(
            settings: .test(base: ["OTHER_SWIFT_FLAGS": .array(["$(inherited)"])]),
            targets: [.test(settings: .test(base: ["OTHER_SWIFT_FLAGS": .string("-DFEATURE")]))]
        ) : Project.test(settings: .test(base: [:]), type: .external(hash: nil))

        let cached = try await hash(
            project: project,
            root: root,
            enableCaching: true,
            enableCachingPrefixMapping: false,
            casPluginPath: plugin
        )
        let uncached = try await hash(project: project, root: root, enableCaching: false, enableCachingPrefixMapping: false)

        #expect(atTargetLevel ? cached == uncached : cached != uncached)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController, arguments: [false, true])
    func hash_withPrefixMappingOptOut_keepsRemoteCacheFlagsProductNeutral(isExternal: Bool) async throws {
        let controller = try #require(XcodeController.mocked)
        given(controller).selectedVersion().willReturn(Version(27, 0, 0))
        let root = try #require(FileSystem.temporaryTestDirectory)
        let plugin = root.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().writeText("plugin", at: plugin)
        let project = Project.test(
            settings: .test(base: ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DFEATURE"])]),
            type: isExternal ? .external(hash: nil) : .local
        )

        let cached = try await hash(
            project: project,
            root: root,
            enableCaching: true,
            enableCachingPrefixMapping: false,
            casPluginPath: plugin
        )
        let uncached = try await hash(project: project, root: root, enableCaching: false, enableCachingPrefixMapping: false)

        #expect(cached == uncached)
    }
}
