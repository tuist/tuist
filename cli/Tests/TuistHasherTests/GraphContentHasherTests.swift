import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistTesting
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
    func contentHashes_emptyGraph() async throws {
        // Given
        let graph = Graph.test()

        // When
        let hashes = try await subject.contentHashes(
            for: graph,
            include: { _ in true },
            destination: nil,
            additionalStrings: []
        )

        // Then
        #expect(hashes == Dictionary())
    }

    @Test
    func contentHashes_returnsOnlyFrameworks() async throws {
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
            destination: nil,
            additionalStrings: []
        )
        let hashedTargets: [GraphTarget] = hashes.keys.sorted { left, right -> Bool in
            left.path.pathString < right.path.pathString
        }
        .sorted(by: { $0.target.name < $1.target.name })

        // Then
        #expect(hashedTargets == expectedCachableTargets)
    }
}
