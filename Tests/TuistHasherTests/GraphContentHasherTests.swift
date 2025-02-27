import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupportTesting
import XcodeGraph

@testable import TuistHasher

struct GraphContentHasherTests {
    private let fileSystem = FileSystem()
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private var subject: GraphContentHasher!

    init() {
        subject = GraphContentHasher(contentHasher: ContentHasher())
    }

    @Test
    func test_contentHashes_emptyGraph() async throws {
        // Given
        let graph = Graph.test()

        // When
        let hashes = try await subject.contentHashes(for: graph, include: { _ in true }, additionalStrings: [])

        // Then
        #expect(hashes == Dictionary())
    }

    @Test
    func test_contentHashes_returnsOnlyFrameworks() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let frameworkATarget: Target = .test(
            name: "FrameworkA",
            product: .framework,
            infoPlist: nil,
            entitlements: nil
        )
        let frameworkBTarget: Target = .test(
            name: "FrameworkB",
            product: .framework,
            infoPlist: nil,
            entitlements: nil
        )
        let appTarget: Target = .test(
            name: "App",
            product: .app,
            infoPlist: nil,
            entitlements: nil
        )
        let dynamicLibraryTarget: Target = .test(
            name: "DynamicLibrary",
            product: .dynamicLibrary,
            infoPlist: nil,
            entitlements: nil
        )
        let staticFrameworkTarget: Target = .test(
            name: "StaticFramework",
            product: .staticFramework,
            infoPlist: nil,
            entitlements: nil
        )

        let project: Project = .test(
            path: path,
            targets: [frameworkATarget, frameworkBTarget, appTarget, dynamicLibraryTarget, staticFrameworkTarget]
        )
        let frameworkTarget = GraphTarget.test(
            path: path,
            target: frameworkATarget,
            project: project
        )
        let secondFrameworkTarget = GraphTarget.test(
            path: path,
            target: frameworkBTarget,
            project: project
        )
        let graph = Graph.test(
            path: path,
            projects: [project.path: project]
        )

        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget].sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try await subject.contentHashes(
            for: graph,
            include: {
                $0.target.product == .framework
            },
            additionalStrings: []
        )
        let hashedTargets: [GraphTarget] = hashes.keys.sorted { left, right -> Bool in
            left.path.pathString < right.path.pathString
        }
        .sorted(by: { $0.target.name < $1.target.name })

        // Then
        #expect(hashedTargets == expectedCachableTargets)
    }

    @Test
    func test_contentHashes_with_lock_file_in_root() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "GraphContentHasherTests") { temporaryDirectory in
            // Given
            let contentHasher = MockContentHashing()
            given(contentHasher)
                .hash(path: .any)
                .willProduce { $0.pathString }
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(temporaryDirectory)
            let lockFilePath = temporaryDirectory.appending(component: ".package.resolved")
            try await fileSystem.touch(lockFilePath)
            let targetContentHasher = MockTargetContentHashing()
            given(targetContentHasher)
                .contentHash(
                    for: .any,
                    hashedTargets: .any,
                    hashedPaths: .any,
                    additionalStrings: .any
                )
                .willProduce { graphTarget, _, _, additionalStrings in
                    TargetContentHash(
                        hash: graphTarget.target.name + "-" + additionalStrings.joined(separator: "-"),
                        hashedPaths: [:]
                    )
                }
            let subject = GraphContentHasher(
                contentHasher: contentHasher,
                targetContentHasher: targetContentHasher,
                rootDirectoryLocator: rootDirectoryLocator
            )

            // When
            let got = try await subject.contentHashes(
                for: .test(
                    path: temporaryDirectory,
                    projects: [
                        temporaryDirectory: .test(
                            targets: [
                                .test(
                                    name: "TargetA"
                                ),
                            ]
                        ),
                    ]
                ),
                include: { _ in true },
                additionalStrings: []
            )

            // Then
            #expect(Array(got.values) == ["TargetA-\(lockFilePath)"])
        }
    }

    @Test
    func test_contentHashes_with_lock_file_in_xcode_project() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "GraphContentHasherTests") { temporaryDirectory in
            // Given
            let contentHasher = MockContentHashing()
            given(contentHasher)
                .hash(path: .any)
                .willProduce { $0.pathString }
            let targetContentHasher = MockTargetContentHashing()
            given(targetContentHasher)
                .contentHash(
                    for: .any,
                    hashedTargets: .any,
                    hashedPaths: .any,
                    additionalStrings: .any
                )
                .willProduce { graphTarget, _, _, additionalStrings in
                    TargetContentHash(
                        hash: graphTarget.target.name + "-" + additionalStrings.joined(separator: "-"),
                        hashedPaths: [:]
                    )
                }
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(nil)
            let subject = GraphContentHasher(
                contentHasher: contentHasher,
                targetContentHasher: targetContentHasher,
                rootDirectoryLocator: rootDirectoryLocator
            )
            let lockFilePath = temporaryDirectory.appending(
                components: "App.xcodeproj",
                "project.xcworkspace",
                "xcshareddata",
                "swiftpm",
                "Package.resolved"
            )
            try await fileSystem.makeDirectory(at: lockFilePath.parentDirectory)
            try await fileSystem.touch(lockFilePath)

            // When
            let got = try await subject.contentHashes(
                for: .test(
                    path: temporaryDirectory,
                    projects: [
                        temporaryDirectory: .test(
                            targets: [
                                .test(
                                    name: "TargetA"
                                ),
                            ]
                        ),
                    ]
                ),
                include: { _ in true },
                additionalStrings: []
            )

            // Then
            #expect(Array(got.values) == ["TargetA-\(lockFilePath)"])
        }
    }

    @Test
    func test_contentHashes_with_lock_file_in_xcode_workspace() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "GraphContentHasherTests") { temporaryDirectory in
            // Given
            let contentHasher = MockContentHashing()
            given(contentHasher)
                .hash(path: .any)
                .willProduce { $0.pathString }
            let targetContentHasher = MockTargetContentHashing()
            given(targetContentHasher)
                .contentHash(
                    for: .any,
                    hashedTargets: .any,
                    hashedPaths: .any,
                    additionalStrings: .any
                )
                .willProduce { graphTarget, _, _, additionalStrings in
                    TargetContentHash(
                        hash: graphTarget.target.name + "-" + additionalStrings.joined(separator: "-"),
                        hashedPaths: [:]
                    )
                }
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(nil)
            let subject = GraphContentHasher(
                contentHasher: contentHasher,
                targetContentHasher: targetContentHasher,
                rootDirectoryLocator: rootDirectoryLocator
            )
            let lockFilePath = temporaryDirectory.appending(
                components: "App.xcworkspace",
                "xcshareddata",
                "swiftpm",
                "Package.resolved"
            )
            try await fileSystem.makeDirectory(at: lockFilePath.parentDirectory)
            try await fileSystem.touch(lockFilePath)

            // When
            let got = try await subject.contentHashes(
                for: .test(
                    path: temporaryDirectory,
                    projects: [
                        temporaryDirectory: .test(
                            targets: [
                                .test(
                                    name: "TargetA"
                                ),
                            ]
                        ),
                    ]
                ),
                include: { _ in true },
                additionalStrings: []
            )

            // Then
            #expect(Array(got.values) == ["TargetA-\(lockFilePath)"])
        }
    }
}
