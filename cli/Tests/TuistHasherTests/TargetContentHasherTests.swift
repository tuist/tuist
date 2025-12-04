import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct TargetContentHasherTests {
    private var contentHasher: MockContentHashing!
    private var coreDataModelsContentHasher: MockCoreDataModelsContentHashing!
    private var sourceFilesContentHasher: MockSourceFilesContentHashing!
    private var targetScriptsContentHasher: MockTargetScriptsContentHashing!
    private var resourcesContentHasher: MockResourcesContentHashing!
    private var copyFilesContentHasher: MockCopyFilesContentHashing!
    private var headersContentHasher: MockHeadersContentHashing!
    private var deploymentTargetContentHasher: MockDeploymentTargetsContentHashing!
    private var plistContentHasher: MockPlistContentHashing!
    private var settingsContentHasher: MockSettingsContentHashing!
    private var dependenciesContentHasher: MockDependenciesContentHashing!
    private var subject: TargetContentHasher!

    init() async throws {
        contentHasher = MockContentHashing()
        coreDataModelsContentHasher = MockCoreDataModelsContentHashing()
        sourceFilesContentHasher = MockSourceFilesContentHashing()
        targetScriptsContentHasher = MockTargetScriptsContentHashing()
        resourcesContentHasher = MockResourcesContentHashing()
        copyFilesContentHasher = MockCopyFilesContentHashing()
        headersContentHasher = MockHeadersContentHashing()
        deploymentTargetContentHasher = MockDeploymentTargetsContentHashing()
        plistContentHasher = MockPlistContentHashing()
        settingsContentHasher = MockSettingsContentHashing()
        dependenciesContentHasher = MockDependenciesContentHashing()
        subject = TargetContentHasher(
            contentHasher: contentHasher,
            sourceFilesContentHasher: sourceFilesContentHasher,
            targetScriptsContentHasher: targetScriptsContentHasher,
            coreDataModelsContentHasher: coreDataModelsContentHasher,
            resourcesContentHasher: resourcesContentHasher,
            copyFilesContentHasher: copyFilesContentHasher,
            headersContentHasher: headersContentHasher,
            deploymentTargetContentHasher: deploymentTargetContentHasher,
            plistContentHasher: plistContentHasher,
            settingsContentHasher: settingsContentHasher,
            dependenciesContentHasher: dependenciesContentHasher
        )

        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: "-") }
        given(contentHasher).hash(.any).willProduce { (value: String) -> String in
            return value
        }
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.pathString }

        given(settingsContentHasher)
            .hash(settings: .any)
            .willReturn("settings_hash")

        given(sourceFilesContentHasher)
            .hash(identifier: .any, sources: .any)
            .willReturn(MerkleNode(hash: "sources_hash", identifier: "sources"))
        given(resourcesContentHasher)
            .hash(identifier: .any, resources: .any)
            .willReturn(MerkleNode(hash: "resources_hash", identifier: "resources"))
        given(copyFilesContentHasher)
            .hash(identifier: .any, copyFiles: .any)
            .willReturn(MerkleNode(hash: "copy_files_hash", identifier: "copy_files"))
        given(coreDataModelsContentHasher!)
            .hash(coreDataModels: .any)
            .willReturn("core_data_models_hash")
        given(dependenciesContentHasher)
            .hash(graphTarget: .any, hashedTargets: .any, hashedPaths: .any)
            .willReturn(DependenciesContentHash(hashedPaths: [:], hash: "dependencies_hash"))
        given(targetScriptsContentHasher)
            .hash(targetScripts: .any, sourceRootPath: .any)
            .willReturn("target_scripts_hash")
        given(contentHasher)
            .hash(Parameter<[String: String]>.any)
            .willReturn("dictionary_hash")
        given(deploymentTargetContentHasher)
            .hash(deploymentTargets: .any)
            .willReturn("deployment_targets_hash")
    }

    @Test func hash_when_targetBelongsToExternalProjectWithHash() async throws {
        // Given
        let target = GraphTarget.test(project: .test(type: .external(hash: "hash")))

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: nil
        )

        // Then
        #expect(got.hash == "hash-Target-app-settings_hash-settings_hash-dependencies_hash-iPad-iPhone")
        #expect(
            got.subhashes == TargetContentHashSubhashes(
                dependencies: "dependencies_hash",
                projectSettings: "settings_hash",
                targetSettings: "settings_hash",
                external: "hash"
            )
        )
    }

    @Test func hash_when_targetBelongsToExternalProjectWithHash_with_additional_string() async throws {
        // Given
        let target = GraphTarget.test(project: .test(type: .external(hash: "hash")))

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: nil,
            additionalStrings: ["additional_string_one", "additional_string_two"]
        )

        // Then
        #expect(
            got.hash ==
                "hash-Target-app-settings_hash-settings_hash-dependencies_hash-iPad-iPhone-additional_string_one-additional_string_two"
        )
        #expect(
            got.subhashes == TargetContentHashSubhashes(
                dependencies: "dependencies_hash",
                projectSettings: "settings_hash",
                targetSettings: "settings_hash",
                additionalStrings: ["additional_string_one", "additional_string_two"],
                external: "hash"
            )
        )
    }

    @Test func hash_with_additional_strings() async throws {
        // Given
        let target = GraphTarget.test(project: .test())

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: .test(
                device: .test(name: "iPhone 16"),
                runtime: .test(name: "iOS-16")
            ),
            additionalStrings: ["additional_string"]
        )

        // Then
        #expect(
            got.hash ==
                """
                Target-app-io.tuist.Target-Target-dependencies_hash-sources_hash-resources_hash-copy_files_hash\
                -core_data_models_hash-target_scripts_hash-dictionary_hash-iPad-iPhone-additional_string-iPad\
                -iPhone-deployment_targets_hash-settings_hash-settings_hash
                """
        )
        #expect(
            got.subhashes == TargetContentHashSubhashes(
                sources: "sources_hash",
                resources: "resources_hash",
                copyFiles: "copy_files_hash",
                coreDataModels: "core_data_models_hash",
                targetScripts: "target_scripts_hash",
                dependencies: "dependencies_hash",
                environment: "dictionary_hash",
                deploymentTarget: "deployment_targets_hash",
                projectSettings: "settings_hash",
                targetSettings: "settings_hash",
                additionalStrings: ["additional_string"]
            )
        )
    }

    @Test func hash_with_buildable_folders() async throws {
        // Given
        let target = GraphTarget.test(target: .test(buildableFolders: [
            BuildableFolder(
                path: try AbsolutePath(validating: "/test/Resources"),
                exceptions: BuildableFolderExceptions(exceptions: [
                    BuildableFolderException(
                        excluded: [],
                        compilerFlags: [:],
                        publicHeaders: ["/test/headers/private/public.h"],
                        privateHeaders: ["/test/headers/public.h"]
                    ),
                ]),
                resolvedFiles: [BuildableFolderFile(
                    path: try AbsolutePath(validating: "/test/Resources/Image.png"),
                    compilerFlags: nil
                )]
            ),
            BuildableFolder(
                path: try AbsolutePath(validating: "/test/Sources"),
                exceptions: BuildableFolderExceptions(exceptions: [
                    BuildableFolderException(
                        excluded: [],
                        compilerFlags: [:],
                        publicHeaders: ["/test/headers/public.h"],
                        privateHeaders: ["/test/headers/private.h"]
                    ),
                ]),
                resolvedFiles: [
                    BuildableFolderFile(
                        path: try AbsolutePath(validating: "/test/Sources/File.swift"),
                        compilerFlags: "compiler-flags"
                    ),
                    BuildableFolderFile(
                        path: try AbsolutePath(validating: "/test/headers/public.h"),
                        compilerFlags: nil
                    ),
                    BuildableFolderFile(
                        path: try AbsolutePath(validating: "/test/headers/private.h"),
                        compilerFlags: nil
                    ),
                ]
            ),
        ]), project: .test())

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: .test(
                device: .test(name: "iPhone 16"),
                runtime: .test(name: "iOS-16")
            ),
            additionalStrings: []
        )

        // Then
        #expect(
            got.hash ==
                """
                Target-app-io.tuist.Target-Target-dependencies_hash-sources_hash-resources_hash-copy_files_hash-core_data_models_hash-target_scripts_hash-dictionary_hash-iPad-iPhone-/test/Resources/Image.png--/test/Sources/File.swift-compiler-flags-/test/headers/private.h--private-header-/test/headers/public.h--public-header-iPad-iPhone-deployment_targets_hash-settings_hash-settings_hash
                """
        )
        #expect(
            got.subhashes == TargetContentHashSubhashes(
                sources: "sources_hash",
                resources: "resources_hash",
                copyFiles: "copy_files_hash",
                coreDataModels: "core_data_models_hash",
                targetScripts: "target_scripts_hash",
                dependencies: "dependencies_hash",
                environment: "dictionary_hash",
                deploymentTarget: "deployment_targets_hash",
                projectSettings: "settings_hash",
                targetSettings: "settings_hash",
                buildableFolders:
                "/test/Resources/Image.png--/test/Sources/File.swift-compiler-flags-/test/headers/private.h--private-header-/test/headers/public.h--public-header"
            )
        )
    }

    @Test func hash_with_destination() async throws {
        // Given
        let target = GraphTarget.test(
            target: .test(
                product: .uiTests
            ),
            project: .test()
        )

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            destination: .test(
                device: .test(
                    name: "iPhone 16",
                    runtimeIdentifier: "iOS-16"
                )
            ),
            additionalStrings: []
        )

        // Then
        #expect(
            got.hash.contains("iPhone 16") == true
        )
        #expect(
            got.hash.contains("iOS-16") == true
        )
        #expect(
            got.subhashes == TargetContentHashSubhashes(
                sources: "sources_hash",
                resources: "resources_hash",
                copyFiles: "copy_files_hash",
                coreDataModels: "core_data_models_hash",
                targetScripts: "target_scripts_hash",
                dependencies: "dependencies_hash",
                environment: "dictionary_hash",
                deploymentTarget: "deployment_targets_hash",
                projectSettings: "settings_hash",
                targetSettings: "settings_hash"
            )
        )
    }
}
