import Foundation
import Mockable
import Path
import Testing
import TuistSupport
import XcodeGraph
import XcodeMetadata
import XCTest

@testable import TuistCore
@testable import TuistTesting

final class GraphLoaderTests: TuistUnitTestCase {
    private var stubbedFrameworks = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedLibraries = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedXCFrameworks = [AbsolutePath: XCFrameworkMetadata]()
    private var frameworkMetadataProvider: MockFrameworkMetadataProvider!
    private var libraryMetadataProvider: MockLibraryMetadataProvider!
    private var xcframeworkMetadataProvider: MockXCFrameworkMetadataProviding!

    override func setUpWithError() throws {
        frameworkMetadataProvider = makeFrameworkMetadataProvider()
        libraryMetadataProvider = makeLibraryMetadataProvider()
        xcframeworkMetadataProvider = makeXCFrameworkMetadataProvider()
    }

    // MARK: - Load Workspace

    func test_loadWorkspace_unreferencedProjectsAreExcluded() async throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.workspace, workspace)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
        ])
        XCTAssertTrue(graph.projects.values.flatMap(\.targets).isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadWorkspace_unlinkedReferencedProjectsAreIncluded() async throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])
        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.workspace, workspace)
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertTrue(graph.projects.values.flatMap(\.targets).isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadWorkspace_linkedReferencedProjectsAreIncluded() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.workspace, workspace.replacing(projects: ["/A", "/B"]))
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Load Project

    func test_loadProject_unlinkedProjectsAreExcluded() async throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let subject = makeSubject()
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
        ])
        XCTAssertTrue(graph.projects.values.flatMap(\.targets).isEmpty)
        XCTAssertTrue(graph.dependencies.isEmpty)
    }

    func test_loadProject_linkedProjectsAreIncluded() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let subject = makeSubject()
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.projects, [
            "/A": projectA,
            "/B": projectB,
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Frameworks

    func test_loadWorkspace_frameworkDependency() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.framework(path: "/Frameworks/F1.framework", status: .required)])
        let targetB = Target.test(name: "B", dependencies: [.framework(path: "/Frameworks/F2.framework", status: .required)])
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
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

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
                    status: .required
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
                    status: .required
                ),
            ]),
        ])
    }

    func test_loadWorkspace_frameworkDependencyReferencedMultipleTimes() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.framework(path: "/Frameworks/F.framework", status: .required)])
        let targetB = Target.test(name: "B", dependencies: [.framework(path: "/Frameworks/F.framework", status: .required)])
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
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        let frameworkDependency: GraphDependency = .framework(
            path: "/Frameworks/F.framework",
            binaryPath: "/Frameworks/F.framework/F",
            dsymPath: nil,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.arm64],
            status: .required
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

    func test_loadWorkspace_libraryDependency() async throws {
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
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

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

    func test_loadWorkspace_xcframeworkDependency() async throws {
        // Given
        let targetA = Target.test(
            name: "A",
            dependencies: [.xcframework(path: "/XCFrameworks/XF1.xcframework", expectedSignature: nil, status: .required)]
        )
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        stubXCFramework(
            metadata: .init(
                path: "/XCFrameworks/XF1.xcframework",
                infoPlist: .test(),
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )

        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
            ]
        )

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .testXCFramework(
                    path: "/XCFrameworks/XF1.xcframework",
                    infoPlist: .test(),
                    linking: .dynamic,
                    mergeable: false,
                    status: .required
                ),
            ]),
        ])
    }

    func test_loadWorkspace_mergeableXCFrameworkDependency() async throws {
        // Given
        let targetA = Target.test(
            name: "A",
            dependencies: [.xcframework(path: "/XCFrameworks/XF1.xcframework", expectedSignature: nil, status: .required)]
        )
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        stubXCFramework(
            metadata: .init(
                path: "/XCFrameworks/XF1.xcframework",
                infoPlist: .test(),
                linking: .dynamic,
                mergeable: true,
                status: .required,
                macroPath: nil
            )
        )

        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
            ]
        )

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .testXCFramework(
                    path: "/XCFrameworks/XF1.xcframework",
                    infoPlist: .test(),
                    linking: .dynamic,
                    mergeable: true,
                    status: .required
                ),
            ]),
        ])
    }

    func test_loadWorkspace_xcframeworkDependencyWithDifferentStatusPerTarget() async throws {
        // Given
        let targetA = Target.test(
            name: "A",
            dependencies: [.xcframework(path: "/XCFrameworks/XF.xcframework", expectedSignature: nil, status: .required)]
        )
        let targetB = Target.test(
            name: "B",
            dependencies: [.xcframework(path: "/XCFrameworks/XF.xcframework", expectedSignature: nil, status: .optional)]
        )
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])

        stubXCFramework(
            metadata: .init(
                path: "/XCFrameworks/XF.xcframework",
                infoPlist: .test(),
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )

        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
            ]
        )

        // Then
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .testXCFramework(
                    path: "/XCFrameworks/XF.xcframework",
                    infoPlist: .test(),
                    linking: .dynamic,
                    mergeable: false,
                    status: .required
                ),
            ]),
            .target(name: "B", path: "/B"): Set([
                .testXCFramework(
                    path: "/XCFrameworks/XF.xcframework",
                    infoPlist: .test(),
                    linking: .dynamic,
                    mergeable: false,
                    status: .optional
                ),
            ]),
        ])
    }

    // MARK: - SDKs

    func test_loadWorkspace_sdkDependency() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.sdk(name: "libc++.tbd", status: .required)])
        let targetB = Target.test(name: "B", dependencies: [.sdk(name: "SwiftUI.framework", status: .optional)])
        let targetC = Target.test(name: "C", dependencies: [.xctest])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA, targetB, targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
            ]
        )

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

    func test_loadWorkspace_packages() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [
            .package(product: "PackageLibraryA1", type: .runtime),
        ])
        let targetB = Target.test(name: "B", dependencies: [
            .package(product: "PackageLibraryA2", type: .runtime),
        ])
        let targetC = Target.test(name: "C", dependencies: [
            .package(product: "PackageLibraryB", type: .runtime),
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
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
                projectB,
                projectC,
            ]
        )

        // Then

        // Note: the following is a reflection of the current implementation
        // which has a few limitation / bugs when it comes to identifying the same
        // package referenced by multiple projects/
        XCTAssertEqual(graph.packages, [
            "/A": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/B": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/C": ["https://example.com/package-library-b": .remote(
                url: "https://example.com/package-library-b",
                requirement: .branch("testing")
            )],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackageLibraryA1", type: .runtime),
            ]),
            .target(name: "B", path: "/B"): Set([
                .packageProduct(path: "/B", product: "PackageLibraryA2", type: .runtime),
            ]),
            .target(name: "C", path: "/C"): Set([
                .packageProduct(path: "/C", product: "PackageLibraryB", type: .runtime),
            ]),
        ])
    }

    func test_loadWorkspace_package_plugin() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [
            .package(product: "PackagePlugin", type: .plugin),
        ])

        let projectA = Project.test(path: "/A", name: "A", targets: [targetA], packages: [
            .local(path: "/Packages/PackagePlugin"),
        ])

        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
            ]
        )

        // Then
        XCTAssertEqual(graph.packages, [
            "/A": ["/Packages/PackagePlugin": .local(path: "/Packages/PackagePlugin")],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackagePlugin", type: .plugin),
            ]),
        ])
    }

    func test_loadWorkspace_package_embedded() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [
            .package(product: "PackageEmbedded", type: .runtimeEmbedded),
        ])

        let projectA = Project.test(path: "/A", name: "A", targets: [targetA], packages: [
            .local(path: "/Packages/PackageEmbedded"),
        ])

        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])

        let subject = makeSubject()

        // When
        let graph = try await subject.loadWorkspace(
            workspace: workspace,
            projects: [
                projectA,
            ]
        )

        // Then
        XCTAssertEqual(graph.packages, [
            "/A": ["/Packages/PackageEmbedded": .local(path: "/Packages/PackageEmbedded")],
        ])
        XCTAssertEqual(graph.dependencies, [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackageEmbedded", type: .runtimeEmbedded),
            ]),
        ])
    }

    // MARK: - Error Cases

    func test_loadWorkspace_missingProjectReferenceInWorkspace() async throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/Missing"])
        let subject = makeSubject()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            ),
            GraphLoadingError.missingProject("/Missing")
        )
    }

    func test_loadWorkspace_missingProjectReferenceInDependency() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            ),
            GraphLoadingError.missingProject("/Missing")
        )
    }

    func test_loadWorkspace_missingTargetReferenceInLocalProject() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.target(name: "Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            ),
            GraphLoadingError.targetNotFound("Missing", "/A")
        )
    }

    func test_loadWorkspace_missingTargetReferenceInOtherProject() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/B")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])
        let subject = makeSubject()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                ]
            ),
            GraphLoadingError.targetNotFound("Missing", "/B")
        )
    }

    // MARK: - Helpers

    private func makeSubject() -> GraphLoader {
        GraphLoader(
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
                status: .required
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

    private func makeXCFrameworkMetadataProvider() -> MockXCFrameworkMetadataProviding {
        let provider = MockXCFrameworkMetadataProviding()
        given(provider).loadMetadata(at: .any, expectedSignature: .any, status: .any).willProduce { [weak self] path, _, _ in
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

struct GraphLoaderXCFrameworkSignatureTests {
    private let signature = XCFrameworkSignature.signedWithAppleCertificate(teamIdentifier: "TEAM", teamName: "Vendor")
    private let path: AbsolutePath = "/Frameworks/SDK.xcframework"
    private let subject: GraphLoader

    init() {
        let provider = MockXCFrameworkMetadataProviding()
        given(provider).loadMetadata(at: .any, expectedSignature: .any, status: .any).willProduce { path, signature, status in
            XCFrameworkMetadata(
                path: path,
                infoPlist: .test(),
                linking: .dynamic,
                mergeable: false,
                status: status,
                macroPath: nil,
                expectedSignature: signature
            )
        }
        subject = GraphLoader(
            frameworkMetadataProvider: MockFrameworkMetadataProvider(),
            libraryMetadataProvider: MockLibraryMetadataProvider(),
            xcframeworkMetadataProvider: provider,
            systemFrameworkMetadataProvider: SystemFrameworkMetadataProvider()
        )
    }

    @Test(arguments: [false, true])
    func sharesExplicitSignatureWithoutChangingLinkageOrConditions(explicitFirst: Bool) async throws {
        let app = Project.test(path: "/App", targets: [
            .test(name: "App", dependencies: [
                .xcframework(path: path, expectedSignature: nil, status: .required, condition: .when([.ios])),
                .xcframework(path: "/Other/SDK.xcframework", expectedSignature: nil, status: .required),
            ]),
        ])
        let feature = Project.test(path: "/Feature", targets: [
            .test(name: "Feature", dependencies: [
                .xcframework(path: path, expectedSignature: signature, status: .optional, condition: .when([.macos])),
            ]),
        ])
        let projects = explicitFirst ? [feature, app] : [app, feature]

        let graph = try await subject.loadWorkspace(
            workspace: .test(projects: projects.map(\.path)),
            projects: projects
        )

        let appDependency = dependency(expectedSignature: "AppleDeveloperProgram:TEAM:Vendor")
        let featureDependency = dependency(expectedSignature: "AppleDeveloperProgram:TEAM:Vendor", status: .optional)
        #expect(graph.dependencies[.target(name: "App", path: "/App")] == [
            appDependency,
            .testXCFramework(path: "/Other/SDK.xcframework"),
        ])
        #expect(graph.dependencies[.target(name: "Feature", path: "/Feature")] == [featureDependency])
        #expect(graph
            .dependencyConditions[GraphEdge(from: .target(name: "App", path: "/App"), to: appDependency)] == .when([.ios]))
        #expect(graph
            .dependencyConditions[GraphEdge(from: .target(name: "Feature", path: "/Feature"), to: featureDependency)] ==
            .when([.macos]))
        #expect(graph.projects[app.path] == app)
        #expect(graph.projects[feature.path] == feature)
    }

    @Test(arguments: [
        (nil, nil, nil),
        (.unsigned, nil, nil),
        (.selfSigned(fingerprint: "fingerprint"), .selfSigned(fingerprint: "fingerprint"), "SelfSigned:fingerprint"),
        (
            .signedWithAppleCertificate(teamIdentifier: "TEAM", teamName: "Vendor"),
            .signedWithAppleCertificate(teamIdentifier: "TEAM", teamName: "Vendor"),
            "AppleDeveloperProgram:TEAM:Vendor"
        ),
    ] as [(XCFrameworkSignature?, XCFrameworkSignature?, String?)])
    func preservesConsistentSignatures(
        first: XCFrameworkSignature?, second: XCFrameworkSignature?, expectedSignature: String?
    ) async throws {
        let project = Project.test(targets: [
            .test(name: "First", dependencies: [.xcframework(path: path, expectedSignature: first, status: .required)]),
            .test(name: "Second", dependencies: [.xcframework(path: path, expectedSignature: second, status: .required)]),
        ])

        let graph = try await subject.loadWorkspace(workspace: .test(projects: [project.path]), projects: [project])

        let expected = dependency(expectedSignature: expectedSignature)
        #expect(graph.dependencies[.target(name: "First", path: project.path)] == [expected])
        #expect(graph.dependencies[.target(name: "Second", path: project.path)] == [expected])
    }

    @Test(arguments: [
        XCFrameworkSignature.unsigned,
        .selfSigned(fingerprint: "different"),
        .signedWithAppleCertificate(teamIdentifier: "OTHER", teamName: "Other vendor"),
    ], [false, true])
    func rejectsConflictingExplicitExpectations(other: XCFrameworkSignature, reversed: Bool) async throws {
        let first = Project.test(path: "/First", targets: [
            .test(dependencies: [.xcframework(path: path, expectedSignature: signature, status: .required)]),
        ])
        let second = Project.test(path: "/Second", targets: [
            .test(dependencies: [.xcframework(path: path, expectedSignature: other, status: .required)]),
        ])
        let projects = reversed ? [second, first] : [first, second]

        do {
            _ = try await subject.loadWorkspace(workspace: .test(projects: projects.map(\.path)), projects: projects)
            Issue.record("Conflicting explicit signatures must not be silently replaced")
        } catch let error as GraphLoadingError {
            #expect(error.type == .abort)
            #expect(error.description.contains(path.pathString))
            #expect(error.description.contains("AppleDeveloperProgram:TEAM:Vendor"))
            #expect(error.description.contains(other.signatureString() ?? "unsigned"))
        }
    }

    @Test(arguments: [false, true])
    func mergesConditionsWhenSignatureResolutionCoalescesReferences(unconditional: Bool) async throws {
        let project = Project.test(targets: [
            .test(name: "App", dependencies: [
                .xcframework(
                    path: path,
                    expectedSignature: nil,
                    status: .required,
                    condition: unconditional ? nil : .when([.ios])
                ),
                .xcframework(path: path, expectedSignature: signature, status: .required, condition: .when([.macos])),
            ]),
        ])

        let graph = try await subject.loadWorkspace(workspace: .test(projects: [project.path]), projects: [project])

        let dependency = dependency(expectedSignature: "AppleDeveloperProgram:TEAM:Vendor")
        let target = GraphDependency.target(name: "App", path: project.path)
        #expect(graph.dependencies[target] == [dependency])
        #expect(graph.dependencyConditions[GraphEdge(from: target, to: dependency)] == (unconditional ? nil : .when([
            .ios,
            .macos,
        ])))
    }

    @Test(arguments: [
        (.when([.macos]), nil, .when([.ios, .macos])),
        (nil, nil, nil),
        (.when([.macos]), .when([.ios]), .when([.ios])),
    ] as [(PlatformCondition?, PlatformCondition?, PlatformCondition?)])
    func preservesDirectAndTransitiveLinkConditions(
        featureCondition: PlatformCondition?, frameworkCondition: PlatformCondition?, expectedCondition: PlatformCondition?
    ) async throws {
        let project = Project.test(targets: [
            .test(name: "App", destinations: [.iPhone, .mac], dependencies: [
                .xcframework(path: path, expectedSignature: signature, status: .required, condition: .when([.ios])),
                .target(name: "Feature", condition: featureCondition),
            ]),
            .test(name: "Feature", destinations: [.iPhone, .mac], product: .staticFramework, dependencies: [
                .xcframework(path: path, expectedSignature: nil, status: .required, condition: frameworkCondition),
            ]),
        ])
        let graph = try await subject.loadWorkspace(workspace: .test(projects: [project.path]), projects: [project])

        let references = try GraphTraverser(graph: graph).linkableDependencies(path: project.path, name: "App")
        let frameworks = references.filter {
            if case .xcframework = $0 { return true }
            return false
        }

        #expect(frameworks == [
            .xcframework(
                path: path,
                expectedSignature: "AppleDeveloperProgram:TEAM:Vendor",
                infoPlist: .test(),
                status: .required,
                condition: expectedCondition
            ),
        ])
    }

    @Test func ignoresExpectationsInUnreferencedProjects() async throws {
        let included = Project.test(path: "/Included", targets: [
            .test(dependencies: [.xcframework(path: path, expectedSignature: nil, status: .required)]),
        ])
        let excluded = Project.test(path: "/Excluded", targets: [
            .test(dependencies: [.xcframework(path: path, expectedSignature: signature, status: .required)]),
        ])

        let graph = try await subject.loadWorkspace(
            workspace: .test(projects: [included.path]),
            projects: [included, excluded]
        )

        #expect(graph.dependencies[.target(name: "Target", path: included.path)] == [.testXCFramework(path: path)])
        #expect(graph.projects[excluded.path] == nil)
    }

    private func dependency(expectedSignature: String?, status: LinkingStatus = .required) -> GraphDependency {
        .xcframework(.init(
            path: path,
            infoPlist: .test(),
            linking: .dynamic,
            mergeable: false,
            status: status,
            swiftModules: [],
            moduleMaps: [],
            expectedSignature: expectedSignature
        ))
    }
}

extension GraphLoadingError {
    private var isCycleError: Bool {
        switch self {
        case .circularDependency:
            return true
        default:
            return false
        }
    }
}
