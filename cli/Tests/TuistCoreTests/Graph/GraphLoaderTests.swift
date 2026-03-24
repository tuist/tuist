import Foundation
import Mockable
import Path
import Testing
import TuistSupport
import XcodeGraph
import XcodeMetadata

@testable import TuistCore
@testable import TuistTesting

struct GraphLoaderTests {
    private var stubbedFrameworks = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedLibraries = [AbsolutePath: PrecompiledMetadata]()
    private var stubbedXCFrameworks = [AbsolutePath: XCFrameworkMetadata]()
    private let frameworkMetadataProvider = MockFrameworkMetadataProvider()
    private let libraryMetadataProvider = MockLibraryMetadataProvider()
    private let xcframeworkMetadataProvider = MockXCFrameworkMetadataProviding()

    // MARK: - Load Workspace

    @Test func loadWorkspace_unreferencedProjectsAreExcluded() async throws {
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
        #expect(graph.workspace == workspace)
        #expect(graph.projects == [
            "/A": projectA,
        ])
        #expect(graph.projects.values.flatMap(\.targets).isEmpty)
        #expect(graph.dependencies.isEmpty)
    }

    @Test func loadWorkspace_unlinkedReferencedProjectsAreIncluded() async throws {
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
        #expect(graph.workspace == workspace)
        #expect(graph.projects == [
            "/A": projectA,
            "/B": projectB,
        ])
        #expect(graph.projects.values.flatMap(\.targets).isEmpty)
        #expect(graph.dependencies.isEmpty)
    }

    @Test func loadWorkspace_linkedReferencedProjectsAreIncluded() async throws {
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
        #expect(graph.workspace == workspace.replacing(projects: ["/A", "/B"]))
        #expect(graph.projects == [
            "/A": projectA,
            "/B": projectB,
        ])
        #expect(graph.dependencies == [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Load Project

    @Test func loadProject_unlinkedProjectsAreExcluded() async throws {
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
        #expect(graph.projects == [
            "/A": projectA,
        ])
        #expect(graph.projects.values.flatMap(\.targets).isEmpty)
        #expect(graph.dependencies.isEmpty)
    }

    @Test func loadProject_linkedProjectsAreIncluded() async throws {
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
        #expect(graph.projects == [
            "/A": projectA,
            "/B": projectB,
        ])
        #expect(graph.dependencies == [
            .target(name: "A", path: "/A"): Set([
                .target(name: "B", path: "/B"),
            ]),
        ])
    }

    // MARK: - Frameworks

    @Test mutating func loadWorkspace_frameworkDependency() async throws {
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
        #expect(graph.dependencies == [
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

    @Test mutating func loadWorkspace_frameworkDependencyReferencedMultipleTimes() async throws {
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
        #expect(graph.dependencies == [
            .target(name: "A", path: "/A"): Set([
                frameworkDependency,
            ]),
            .target(name: "B", path: "/B"): Set([
                frameworkDependency,
            ]),
        ])
    }

    // MARK: - Libraries

    @Test mutating func loadWorkspace_libraryDependency() async throws {
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
        #expect(graph.dependencies == [
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

    @Test mutating func loadWorkspace_xcframeworkDependency() async throws {
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
        #expect(graph.dependencies == [
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

    @Test mutating func loadWorkspace_mergeableXCFrameworkDependency() async throws {
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
        #expect(graph.dependencies == [
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

    @Test mutating func loadWorkspace_xcframeworkDependencyWithDifferentStatusPerTarget() async throws {
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
        #expect(graph.dependencies == [
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

    @Test func loadWorkspace_sdkDependency() async throws {
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
        #expect(graph.dependencies == [
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

    @Test func loadWorkspace_packages() async throws {
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
        #expect(graph.packages == [
            "/A": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/B": ["/Packages/PackageLibraryA": .local(path: "/Packages/PackageLibraryA")],
            "/C": ["https://example.com/package-library-b": .remote(
                url: "https://example.com/package-library-b",
                requirement: .branch("testing")
            )],
        ])
        #expect(graph.dependencies == [
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

    @Test func loadWorkspace_package_plugin() async throws {
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
        #expect(graph.packages == [
            "/A": ["/Packages/PackagePlugin": .local(path: "/Packages/PackagePlugin")],
        ])
        #expect(graph.dependencies == [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackagePlugin", type: .plugin),
            ]),
        ])
    }

    @Test func loadWorkspace_package_embedded() async throws {
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
        #expect(graph.packages == [
            "/A": ["/Packages/PackageEmbedded": .local(path: "/Packages/PackageEmbedded")],
        ])
        #expect(graph.dependencies == [
            .target(name: "A", path: "/A"): Set([
                .packageProduct(path: "/A", product: "PackageEmbedded", type: .runtimeEmbedded),
            ]),
        ])
    }

    // MARK: - Error Cases

    @Test func loadWorkspace_missingProjectReferenceInWorkspace() async throws {
        // Given
        let projectA = Project.test(path: "/A", name: "A", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/Missing"])
        let subject = makeSubject()

        // When / Then
        await #expect(throws: GraphLoadingError.missingProject("/Missing")) {
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            )
        }
    }

    @Test func loadWorkspace_missingProjectReferenceInDependency() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        await #expect(throws: GraphLoadingError.missingProject("/Missing")) {
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            )
        }
    }

    @Test func loadWorkspace_missingTargetReferenceInLocalProject() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.target(name: "Missing")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A"])
        let subject = makeSubject()

        // When / Then
        await #expect(throws: GraphLoadingError.targetNotFound("Missing", "/A")) {
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                ]
            )
        }
    }

    @Test func loadWorkspace_missingTargetReferenceInOtherProject() async throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "Missing", path: "/B")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B"])
        let subject = makeSubject()

        // When / Then
        await #expect(throws: GraphLoadingError.targetNotFound("Missing", "/B")) {
            try await subject.loadWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                ]
            )
        }
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

    private mutating func stubFramework(metadata: PrecompiledMetadata) {
        stubbedFrameworks[metadata.path] = metadata
        let stubbedFrameworks = stubbedFrameworks
        frameworkMetadataProvider.loadMetadataStub = { path in
            guard let metadata = stubbedFrameworks[path] else {
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
    }

    private mutating func stubLibrary(metadata: PrecompiledMetadata) {
        stubbedLibraries[metadata.path] = metadata
        let stubbedLibraries = stubbedLibraries
        libraryMetadataProvider.loadMetadataStub = { path, publicHeaders, swiftModuleMap in
            guard let metadata = stubbedLibraries[path] else {
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
    }

    private mutating func stubXCFramework(metadata: XCFrameworkMetadata) {
        stubbedXCFrameworks[metadata.path] = metadata
        let stubbedXCFrameworks = stubbedXCFrameworks
        given(xcframeworkMetadataProvider).loadMetadata(at: .any, expectedSignature: .any, status: .any)
            .willProduce { path, _, _ in
                guard let metadata = stubbedXCFrameworks[path] else {
                    throw XCFrameworkMetadataProviderError.xcframeworkNotFound(path)
                }
                return metadata
            }
    }

    // MARK: - Helper types

    private struct PrecompiledMetadata {
        var path: AbsolutePath
        var linkage: BinaryLinking
        var architectures: [BinaryArchitecture]
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
