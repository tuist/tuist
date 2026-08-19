import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistKit

struct PreselectedXCFrameworkSlicesGraphMapperTests {
    private let fileSystem = FileSystem()
    private let subject = PreselectedXCFrameworkSlicesGraphMapper()

    @Test(.inTemporaryDirectory)
    func map_preselects_unambiguous_framework_slices_for_each_supported_sdk() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Project")
        let xcframeworkPath = projectPath.parentDirectory.appending(component: "Kit.xcframework")

        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "ios-arm64"))
        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "ios-arm64_x86_64-simulator"))
        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "macos-arm64_x86_64"))

        let xcframeworkDependency = GraphDependency.testXCFramework(
            path: xcframeworkPath,
            infoPlist: XCFrameworkInfoPlist(libraries: [
                .test(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .iOS
                ),
                .test(
                    identifier: "ios-arm64_x86_64-simulator",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .iOS,
                    platformVariant: .simulator
                ),
                .test(
                    identifier: "macos-arm64_x86_64",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .macOS
                ),
            ]),
            linking: .static
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App",
                            destinations: [.iPhone, .iPad, .mac],
                            product: .app
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph.dependencies[.target(name: "App", path: projectPath)] == [])

        let settings = try #require(gotGraph.projects[projectPath]?.targets["App"]?.settings?.base)
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos",
        ]))
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphonesimulator",
        ]))
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=macosx*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/macosx",
        ]))
        #expect(settings["OTHER_LDFLAGS[sdk=macosx*]"] == .array([
            "$(inherited)",
            "\"@$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/macosx/App-macosx.resp\"",
        ]))

        let sourceRootPath = try #require(gotGraph.projects[projectPath]?.sourceRootPath)

        #expect(
            gotSideEffects.contains { sideEffect in
                guard case let .symbolicLink(descriptor) = sideEffect else { return false }
                return descriptor.path == sourceRootPath
                    .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx", "Kit.framework") &&
                    descriptor.destination == xcframeworkPath
                    .appending(components: "macos-arm64_x86_64", "Kit.framework")
            }
        )
        let macOSFrameworkDirectory = sourceRootPath
            .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx")
        let expectedResponseFileContents = "-F\(macOSFrameworkDirectory.pathString)\n-framework\nKit\n"
        #expect(
            gotSideEffects.contains { sideEffect in
                guard case let .file(descriptor) = sideEffect else { return false }
                return descriptor.path == sourceRootPath
                    .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx", "App-macosx.resp") &&
                    descriptor.contents.flatMap { String(data: $0, encoding: .utf8) } ==
                    expectedResponseFileContents
            }
        )
    }

    @Test(.inTemporaryDirectory)
    func map_preselects_dynamic_runtime_xcframeworks_and_embeds_selected_slices() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Project")
        let xcframeworkPath = projectPath.parentDirectory.appending(component: "RuntimeKit.xcframework")

        try await makeFramework(named: "RuntimeKit", in: xcframeworkPath.appending(component: "ios-arm64"))
        try await makeFramework(named: "RuntimeKit", in: xcframeworkPath.appending(component: "ios-arm64_x86_64-simulator"))

        let xcframeworkDependency = GraphDependency.testXCFramework(
            path: xcframeworkPath,
            infoPlist: XCFrameworkInfoPlist(libraries: [
                .test(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "RuntimeKit.framework"),
                    platform: .iOS
                ),
                .test(
                    identifier: "ios-arm64_x86_64-simulator",
                    path: try RelativePath(validating: "RuntimeKit.framework"),
                    platform: .iOS,
                    platformVariant: .simulator
                ),
            ]),
            linking: .dynamic
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App",
                            destinations: [.iPhone],
                            product: .app
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph.dependencies[.target(name: "App", path: projectPath)] == [])

        let settings = try #require(gotGraph.projects[projectPath]?.targets["App"]?.settings?.base)
        #expect(settings["OTHER_LDFLAGS[sdk=iphoneos*]"] == .array([
            "$(inherited)",
            "\"@$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos/App-iphoneos.resp\"",
        ]))

        let scripts = try #require(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        #expect(scripts.count == 1)
        let script = try #require(scripts.first)
        #expect(script.name == "Embed Preselected XCFramework Slices")
        #expect(script.order == .post)
        #expect(script.basedOnDependencyAnalysis == true)
        #expect(script.inputPaths.contains(
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos/RuntimeKit.framework"
        ))
        #expect(script.inputPaths.contains(
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos/RuntimeKit.framework/RuntimeKit"
        ))
        #expect(script.inputPaths.contains(
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos/RuntimeKit.framework/Info.plist"
        ))
        #expect(script.outputPaths == [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/RuntimeKit.framework",
        ])

        let embeddedScript = try #require(script.embeddedScript)
        #expect(embeddedScript.contains("rsync --delete -av"))
        #expect(embeddedScript.contains("--filter \"- Headers\""))
        #expect(embeddedScript.contains("--filter \"- PrivateHeaders\""))
        #expect(embeddedScript.contains("--filter \"- Modules\""))
        #expect(embeddedScript.contains("strip_invalid_archs"))
        #expect(embeddedScript.contains("code_sign_if_enabled"))
        #expect(embeddedScript.contains("${CODE_SIGNING_REQUIRED:-}"))
        #expect(embeddedScript.contains("${OTHER_CODE_SIGN_FLAGS:-}"))
        #expect(embeddedScript.contains("iphoneos)"))
        #expect(embeddedScript.contains("iphonesimulator)"))

        let sourceRootPath = try #require(gotGraph.projects[projectPath]?.sourceRootPath)
        #expect(
            gotSideEffects.contains { sideEffect in
                guard case let .symbolicLink(descriptor) = sideEffect else { return false }
                return descriptor.path == sourceRootPath
                    .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "iphoneos", "RuntimeKit.framework") &&
                    descriptor.destination == xcframeworkPath
                    .appending(components: "ios-arm64", "RuntimeKit.framework")
            }
        )
    }

    private func makeFramework(named name: String, in directory: AbsolutePath) async throws {
        let frameworkPath = directory.appending(component: "\(name).framework")
        try await fileSystem.makeDirectory(at: frameworkPath)
    }
}
