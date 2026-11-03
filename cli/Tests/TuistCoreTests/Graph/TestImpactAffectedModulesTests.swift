import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistTesting
import XcodeGraph
import XcodeGraphMapper
@testable import TuistCore

struct TestImpactAffectedModulesTests {
    private struct Golden: Decodable {
        struct ChangedFile: Decodable {
            let path: String
            let affectedModules: [String]?
        }

        struct Scenario: Decodable {
            struct Variant: Decodable {
                let changedFiles: [ChangedFile]?
            }

            let name: String
            let changedFiles: [ChangedFile]?
            let variants: [String: Variant]?
        }

        let scenarios: [Scenario]
    }

    /// The plain Xcode variant of the coverage test selection test bed, mapped as a project without
    /// manifests is, against the modules its golden expectations list for each changed file.
    @Test(.inTemporaryDirectory) func mapsTheTestBedsChangedFilesToTheirTestModules() async throws {
        let repository = try #require(FileSystem.temporaryTestDirectory)
        let testBed = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "CoverageTestSelection"))
        try await FileSystem().copy(
            testBed.appending(components: "xcodeproj", "Shop.xcodeproj"),
            to: repository.appending(component: "Shop.xcodeproj")
        )
        let graph = try await XcodeGraphMapper().map(at: repository.appending(component: "Shop.xcodeproj"))
        let subject = TestImpactAffectedModules(graph: graph)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let golden = try decoder.decode(
            Golden.self,
            from: try Data(contentsOf: testBed.appending(component: "golden.json").url)
        )

        var checked = 0
        for scenario in golden.scenarios {
            let changedFiles = scenario.variants?["xcodeproj"]?.changedFiles ?? scenario.changedFiles ?? []
            // Scenarios that edit the project are classified against the checkout's graph, not this one.
            guard !changedFiles.contains(where: { $0.path.hasSuffix(".xcodeproj/project.pbxproj") }) else { continue }
            for file in changedFiles where !file.path.hasPrefix("bulk/") {
                let got = subject.affectedModules(path: try repository.appending(RelativePath(validating: file.path)))
                #expect(got.map(Set.init) == file.affectedModules.map(Set.init), "\(scenario.name): \(file.path)")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test func attributesFilesInsideABuildableFolderExceptTheExcludedOnes() throws {
        let projectPath = try AbsolutePath(validating: "/Repo")
        let feature = Target.test(
            name: "Feature",
            product: .framework,
            settings: nil,
            buildableFolders: [
                BuildableFolder(
                    path: projectPath.appending(component: "Feature"),
                    exceptions: BuildableFolderExceptions(exceptions: [
                        BuildableFolderException(
                            excluded: [projectPath.appending(components: "Feature", "Scripts")],
                            compilerFlags: [:],
                            publicHeaders: [],
                            privateHeaders: []
                        ),
                    ]),
                    resolvedFiles: []
                ),
            ]
        )
        let featureTests = Target.test(
            name: "FeatureTests",
            product: .unitTests,
            settings: nil,
            sources: [SourceFile(path: projectPath.appending(components: "FeatureTests", "FeatureTests.swift"))]
        )
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Feature.xcodeproj"),
            settings: .test(configurations: [.debug: .test(xcconfig: projectPath.appending(component: "Base.xcconfig"))]),
            targets: [feature, featureTests]
        )
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "FeatureTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
            ]
        )
        let subject = TestImpactAffectedModules(graph: graph)

        // A file the folder doesn't list yet, such as a deleted one, still belongs to it.
        #expect(subject.affectedModules(path: projectPath.appending(components: "Feature", "Deleted.swift")) == ["FeatureTests"])
        #expect(subject.affectedModules(path: projectPath.appending(components: "Feature", "Scripts", "lint.sh")) == [])
        #expect(subject.affectedModules(
            path: projectPath.appending(components: "FeatureTests", "FeatureTests.swift")
        ) == ["FeatureTests"])
        #expect(subject.affectedModules(path: projectPath.appending(component: "Base.xcconfig")) == nil)
        #expect(subject.affectedModules(
            path: projectPath.appending(components: "Feature.xcodeproj", "project.pbxproj")
        ) == nil)
    }
}
