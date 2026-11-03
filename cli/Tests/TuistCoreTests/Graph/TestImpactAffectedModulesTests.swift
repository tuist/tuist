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
    /// The plain Xcode variant of the coverage test selection test bed, mapped as a project without
    /// manifests is, against the modules its golden expectations list for each changed file.
    @Test(.inTemporaryDirectory) func mapsTheTestBedsChangedFilesToTheirTestModules() async throws {
        let repository = try #require(FileSystem.temporaryTestDirectory)
        try await FileSystem().copy(
            SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "CoverageTestSelection/xcodeproj/Shop.xcodeproj")),
            to: repository.appending(component: "Shop.xcodeproj")
        )
        let graph = try await XcodeGraphMapper().map(at: repository.appending(component: "Shop.xcodeproj"))
        let subject = TestImpactAffectedModules(graph: graph)
        let core = ["AppTests", "AppUITests", "CoreTests"]
        let catalog = ["AppTests", "AppUITests", "CatalogTests"]

        let expected: [String: [String]?] = [
            "Core/Sources/Discount.swift": core,
            "Core/Sources/Money.swift": core,
            "Core/Sources/Models.swift": core,
            "Catalog/Sources/Catalog.swift": catalog,
            "Catalog/Sources/Search.swift": catalog,
            "Catalog/Resources/products.json": catalog,
            "App/Resources/Assets.xcassets/Brand.colorset/Contents.json": ["AppTests", "AppUITests"],
            "CoreTests/DiscountTests.swift": ["CoreTests"],
            // The plain project lists its files, so a new one has no owner until it's added.
            "Catalog/Sources/Featured.swift": [],
            "CatalogTests/Fixtures/catalog-fixture.json": [],
            "README.md": [],
            "docs/notes.md": [],
            "Configs/Base.xcconfig": nil,
        ]
        for (path, modules) in expected {
            let got = subject.affectedModules(path: try repository.appending(RelativePath(validating: path)))
            #expect(got == modules, "\(path)")
        }
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
