import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphLoaderTests: TuistUnitTestCase {
    private var stubbedFrameworks = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedLibraries = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedXCFrameworks = [AbsolutePath: XCFrameworkMetadata]()
    private var frameworkMetadataProvider: MockFrameworkMetadataProvider!
    private var libraryMetadataProvider: MockLibraryMetadataProvider!
    private var xcframeworkMetadataProvider: MockXCFrameworkMetadataProvider!

    override func setUpWithError() throws {
        frameworkMetadataProvider = makeFrameworkMetadataProvider()
        libraryMetadataProvider = makeLibraryMetadataProvider()
        xcframeworkMetadataProvider = makeXCFrameworkMetadataProvider()
    }

    // MARK: - Load Workspace

    func test_loadWorkspace_unreferencedProjectsAreExcluded() throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(graph.workspace, workspace)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
        ])
        XCTAssertTrue(graph.targets.isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadWorkspace_unlinkedReferencedProjectsAreIncluded() throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])
        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(graph.workspace, workspace)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertTrue(graph.targets.isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadWorkspace_linkedReferencedProjectsAreIncluded() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(graph.workspace, workspace.replacing(projects: ["/A", "/B"]))
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertEqual(graph.targets, [
            "/A": ["A": targetA],
            "/B": ["B": targetB],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Load Project

    func test_loadProject_unlinkedProjectsAreExcluded() throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let subject = makeSubject()

        // When
        let (loadedProject, graph) = try subject.loadProject(at: "/A", projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(loadedProject, projectA)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
        ])
        XCTAssertTrue(graph.targets.isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadProject_linkedProjectsAreIncluded() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let subject = makeSubject()

        // When
        let (loadedProject, graph) = try subject.loadProject(at: "/A", projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(loadedProject, projectA)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertEqual(graph.targets, [
            "/A": ["A": targetA],
            "/B": ["B": targetB],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Frameworks

    func test_loadWorkspace_frameworkDependency() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.framework(path: "/Frameworks/F1.framework")])
        let targetB = Target.test(name: "B", dependencies: [.framework(path: "/Frameworks/F2.framework")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])

        stubFramework(
            metadata: .init(
                path: "/Frameworks/F1.framework",
                linkage: .dynamic,
                architectures: [.arm64]
            )
        )
        stubFramework(
            metadata: .init(
                path: "/Frameworks/F2.framework",
                linkage: .static,
                architectures: [.x8664]
            )
        )

        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .framework(
                    path: "/Frameworks/F1.framework",
                    binaryPath: "/Frameworks/F1.framework/F1",
                    dsymPath: nil,
                    bcsymbolmapPaths: [],
                    linking: .dynamic,
                    architectures: [.arm64],
                    isCarthage: false
                ),
            ]),
            .target(name: "B", path: "/B"): Set([
                .framework(
                    path: "/Frameworks/F2.framework",
                    binaryPath: "/Frameworks/F2.framework/F2",
                    dsymPath: nil,
                    bcsymbolmapPaths: [],
                    linking: .static,
                    architectures: [.x8664],
                    isCarthage: false
                ),
            ]),
        ])
    }

    func test_loadWorkspace_frameworkDependencyReferencedMultipleTimes() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.framework(path: "/Frameworks/F.framework")])
        let targetB = Target.test(name: "B", dependencies: [.framework(path: "/Frameworks/F.framework")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])

        stubFramework(
            metadata: .init(
                path: "/Frameworks/F.framework",
                linkage: .dynamic,
                architectures: [.arm64]
            )
        )

        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        let frameworkDependency: ValueGraphDependency = .framework(
            path: "/Frameworks/F.framework",
            binaryPath: "/Frameworks/F.framework/F",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            isCarthage: false
        )
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                frameworkDependency,
            ]),
            .target(name: "B", path: "/B"): Set([
                frameworkDependency,
            ]),
        ])
    }

    // MARK: - Libraries

    func test_loadWorkspace_libraryDependency() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [
            .library(path: "/libs/lib1/libL1.dylib", publicHeaders: "/libs/lib1/include", swiftModuleMap: nil),
        ])
        let targetB = Target.test(name: "B", dependencies: [
            .library(
                path: "/libs/lib2/libL2.a",
                publicHeaders: "/libs/lib2/include",
                swiftModuleMap: "/libs/lib2.swiftmodule"
            ),
        ])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])

        stubLibrary(
            metadata: .init(
                path: "/libs/lib1/libL1.dylib",
                linkage: .dynamic,
                architectures: [.arm64]
            )
        )
        stubLibrary(
            metadata: .init(
                path: "/libs/lib2/libL2.a",
                linkage: .static,
                architectures: [.x8664]
            )
        )

        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
        ])

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .library(
                    path: "/libs/lib1/libL1.dylib",
                    publicHeaders: "/libs/lib1/include",
                    linking: .dynamic,
                    architectures: [.arm64],
                    swiftModuleMap: nil
                ),
            ]),
            .target(name: "B", path: "/B"): Set([
                .library(
                    path: "/libs/lib2/libL2.a",
                    publicHeaders: "/libs/lib2/include",
                    linking: .static,
                    architectures: [.x8664],
                    swiftModuleMap: "/libs/lib2.swiftmodule"
                ),
            ]),
        ])
    }

    // MARK: - XCFrameworks

    func test_loadWorkspace_xcframeworkDependency() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.xcFramework(path: "/XCFrameworks/XF1.xcframework")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        stubXCFramework(
            metadata: .init(
                path: "/XCFrameworks/XF1.xcframework",
                infoPlist: .test(),
                primaryBinaryPath: "/XCFrameworks/XF1.xcframework/ios-arm64/XF1",
                linking: .dynamic
            )
        )

        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
        ])

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .xcframework(
                    path: "/XCFrameworks/XF1.xcframework",
                    infoPlist: .test(),
                    primaryBinaryPath: "/XCFrameworks/XF1.xcframework/ios-arm64/XF1",
                    linking: .dynamic
                ),
            ]),
        ])
    }

    // MARK: - SDKs

    func test_loadWorkspace_sdkDependency() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.sdk(name: "libc++.tbd", status: .required)])
        let targetB = Target.test(name: "B", dependencies: [.sdk(name: "SwiftUI.framework", status: .optional)])
        let targetC = Target.test(name: "C", dependencies: [.xctest])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA, targetB, targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
        ])

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .sdk(
                    name: "libc++.tbd",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libc++.tbd",
                    status: .required,
                    source: .system
                ),
            ]),
            .target(name: "B", path: "/A"): Set([
                .sdk(
                    name: "SwiftUI.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework",
                    status: .optional,
                    source: .system
                ),
            ]),
            .target(name: "C", path: "/A"): Set([
                .sdk(
                    name: "XCTest.framework",
                    path: "/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework",
                    status: .required,
                    source: .developer
                ),
            ]),
        ])
    }

    // MARK: - Packages

    func test_loadWorkspace_packages() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [
            .package(product: "PackageLibraryA1"),
        ])
        let targetB = Target.test(name: "B", dependencies: [
            .package(product: "PackageLibraryA2"),
        ])
        let targetC = Target.test(name: "C", dependencies: [
            .package(product: "PackageLibraryB"),
        ])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA], packages: [
            .local(path: "/Packages/PackageLibraryA"),
        ])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB], packages: [
            .local(path: "/Packages/PackageLibraryA"),
        ])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC], packages: [
            .remote(url: "https://example.com/package-library-b", requirement: .branch("testing")),
        ])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])

        let subject = makeSubject()

        // When
        let graph = try subject.loadWorkspace(workspace: workspace, projects: [
            projectA,
            projectB,
            projectC,
        ])

        // Then

        // Note: the following is a reflection of the current implementation
        // which has a few limitation / bugs when it comes to identifying the same
        // package referenced by multiple projects/
        XCTAssertEqual(graph.packages, [
            "/A": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/B": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/C": ["https://example.com/package-library-b": .remote(url: "https://example.com/package-library-b", requirement: .branch("testing"))],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackageLibraryA1"),
            ]),
            .target(name: "B", path: "/B"): Set([
                .packageProduct(path: "/B", product: "PackageLibraryA2"),
            ]),
            .target(name: "C", path: "/C"): Set([
                .packageProduct(path: "/C", product: "PackageLibraryB"),
            ]),
        ])
    }

    // MARK: - Dependency Cycle

    func test_loadProject_localDependencyCycle() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.target(name: "B")])
        let targetB = Target.test(name: "B", dependencies: [.target(name: "C")])
        let targetC = Target.test(name: "C", dependencies: [.target(name: "A")])
        let project = Project.test(path: "/A", name: "A", targets: [targetA, targetB, targetC])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadProject(at: "/A", projects: [
                project,
            ]),
            GraphLoadingError.circularDependency([
                .init(path: "/A", name: "A"),
                .init(path: "/A", name: "B"),
                .init(path: "/A", name: "C"),
            ])
        )
    }

    func test_loadProject_differentProjectDependencyCycle() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [.project(target: "C", path: "/C")])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadProject(at: "/A", projects: [
                projectA,
                projectB,
                projectC,
            ]),
            GraphLoadingError.circularDependency([
                .init(path: "/A", name: "A"),
                .init(path: "/B", name: "B"),
                .init(path: "/C", name: "C"),
            ])
        )
    }

    func test_loadWorkspace_differentProjectDependencyCycle() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [.project(target: "C", path: "/C")])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
                projectB,
                projectC,
            ]),
            GraphLoadingError.circularDependency([
                .init(path: "/A", name: "A"),
                .init(path: "/B", name: "B"),
                .init(path: "/C", name: "C"),
            ])
        )
    }

    func test_loadProject_crossProjectsReferenceWithNoDependencyCycle() throws {
        // Given
        let targetA1 = Target.test(name: "A1", dependencies: [.project(target: "B1", path: "/B")])
        let targetA2 = Target.test(name: "A2", dependencies: [.project(target: "B2", path: "/B")])
        let targetB1 = Target.test(name: "B1", dependencies: [.project(target: "C", path: "/C")])
        let targetB2 = Target.test(name: "B2", dependencies: [])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A2", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA1, targetA2])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB1, targetB2])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let subject = makeSubject()

        // When / Then
        XCTAssertNoThrow(
            try subject.loadProject(at: "/A", projects: [
                projectA,
                projectB,
                projectC,
            ])
        )
    }

    func test_loadWorkspace_crossProjectsReferenceWithNoDependencyCycle() throws {
        // Given
        let targetA1 = Target.test(name: "A1", dependencies: [.project(target: "B1", path: "/B")])
        let targetA2 = Target.test(name: "A2", dependencies: [.project(target: "B2", path: "/B")])
        let targetB1 = Target.test(name: "B1", dependencies: [.project(target: "C", path: "/C")])
        let targetB2 = Target.test(name: "B2", dependencies: [])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A2", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA1, targetA2])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB1, targetB2])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = makeSubject()

        // When / Then
        XCTAssertNoThrow(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
                projectB,
                projectC,
            ])
        )
    }

    func test_loadWorkspace_crossProjectsReferenceWithDependencyCycle() throws {
        // Given
        let targetA1 = Target.test(name: "A1", dependencies: [.project(target: "B1", path: "/B")])
        let targetA2 = Target.test(name: "A2", dependencies: [.project(target: "B2", path: "/B")])
        let targetB1 = Target.test(name: "B1", dependencies: [.project(target: "C1", path: "/C")])
        let targetB2 = Target.test(name: "B2", dependencies: [.project(target: "C2", path: "/C")])
        let targetC1 = Target.test(name: "C1", dependencies: [.project(target: "A2", path: "/A")])
        let targetC2 = Target.test(name: "C2", dependencies: [.project(target: "B1", path: "/B")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA1, targetA2])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB1, targetB2])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC1, targetC2])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsError(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
                projectB,
                projectC,
            ])
        ) { error in
            // need to manually inspect the error as depending on traversal order may result in different nodes getting listed
            let graphError = error as? GraphLoadingError
            XCTAssertNotNil(graphError)
            XCTAssertTrue(graphError?.isCycleError == true)
        }
    }

    // MARK: - Error Cases

    func test_loadWorkspace_missingProjectReferenceInWorkspace() throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/Missing"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
            ]),
            GraphLoadingError.missingProject("/Missing")
        )
    }

    func test_loadWorkspace_missingProjectReferenceInDependency() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
            ]),
            GraphLoadingError.missingProject("/Missing")
        )
    }

    func test_loadWorkspace_missingTargetReferenceInLocalProject() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.target(name: "Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
            ]),
            GraphLoadingError.targetNotFound("Missing", "/A")
        )
    }

    func test_loadWorkspace_missingTargetReferenceInOtherProject() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/B")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])
        let subject = makeSubject()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(workspace: workspace, projects: [
                projectA,
                projectB,
            ]),
            GraphLoadingError.targetNotFound("Missing", "/B")
        )
    }

    // MARK: - Helpers

    private func makeSubject() -> ValueGraphLoader {
        ValueGraphLoader(
            frameworkMetadataProvider: frameworkMetadataProvider,
            libraryMetadataProvider: libraryMetadataProvider,
            xcframeworkMetadataProvider: xcframeworkMetadataProvider,
            systemFrameworkMetadataProvider: SystemFrameworkMetadataProvider()
        )
    }

    private func makeFrameworkMetadataProvider() -> MockFrameworkMetadataProvider {
        let provider = MockFrameworkMetadataProvider()
        provider.loadMetadataStub = { [weak self] path in
            guard let metadata = self?.stubbedFrameworks[path] else {
                throw FrameworkMetadataProviderError.frameworkNotFound(path)
            }
            return FrameworkMetadata(
                path: path,
                binaryPath: path.appending(component: path.basenameWithoutExt),
                dsymPath: nil,
                bcsymbolmapPaths: [],
                linking: metadata.linkage,
                architectures: metadata.architectures,
                isCarthage: false
            )
        }
        return provider
    }

    private func makeLibraryMetadataProvider() -> MockLibraryMetadataProvider {
        let provider = MockLibraryMetadataProvider()
        provider.loadMetadataStub = { [weak self] path, publicHeaders, swiftModuleMap in
            guard let metadata = self?.stubbedLibraries[path] else {
                throw LibraryMetadataProviderError.libraryNotFound(path)
            }
            return LibraryMetadata(
                path: path,
                publicHeaders: publicHeaders,
                swiftModuleMap: swiftModuleMap,
                architectures: metadata.architectures,
                linking: metadata.linkage
            )
        }
        return provider
    }

    private func makeXCFrameworkMetadataProvider() -> MockXCFrameworkMetadataProvider {
        let provider = MockXCFrameworkMetadataProvider()
        provider.loadMetadataStub = { [weak self] path in
            guard let metadata = self?.stubbedXCFrameworks[path] else {
                throw XCFrameworkMetadataProviderError.xcframeworkNotFound(path)
            }
            return metadata
        }
        return provider
    }

    private func stubFramework(metadata: PrecompiledMetadata) {
        stubbedFrameworks[metadata.path] = metadata
    }

    private func stubLibrary(metadata: PrecompiledMetadata) {
        stubbedLibraries[metadata.path] = metadata
    }

    private func stubXCFramework(metadata: XCFrameworkMetadata) {
        stubbedXCFrameworks[metadata.path] = metadata
    }

    // MARK: - Helper types

    private struct PrecompiledMetadata {
        var path: AbsolutePath
        var linkage: BinaryLinking
        var architectures: [BinaryArchitecture]
    }
}

private extension GraphLoadingError {
    var isCycleError: Bool {
        switch self {
        case .circularDependency:
            return true
        default:
            return false
        }
    }
}
