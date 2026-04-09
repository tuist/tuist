import Path
import TuistCore
import TuistGenerator
import XcodeGraph
import XCTest

@testable import TuistTesting

final class ModuleMapMapperTests: TuistUnitTestCase {
    var subject: ModuleMapMapper!

    override func setUp() {
        super.setUp()

        subject = ModuleMapMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_maps_modulemap_build_flag_to_setting() throws {
        // Given
        let workspace = Workspace.test()
        let projectAPath = try temporaryPath().appending(component: "A")
        let projectBPath = try temporaryPath().appending(component: "B")

        let targetA = Target.test(
            name: "A",
            settings: .test(base: [
                "OTHER_CFLAGS": ["Other"],
                "OTHER_SWIFT_FLAGS": "Other",
            ]),
            dependencies: [
                .project(target: "B1", path: projectBPath),
            ]
        )
        let projectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                targetA,
            ]
        )

        let targetB1 = Target.test(
            name: "B1",
            settings: .test(base: [
                "MODULEMAP_FILE": .string(projectBPath.appending(components: "B1", "B1.module").pathString),
                "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B1/include"]),
            ]),
            dependencies: [
                .target(name: "B2"),
            ]
        )
        let targetB2 = Target.test(
            name: "B2",
            settings: .test(base: [
                "MODULEMAP_FILE": .string(projectBPath.appending(components: "B2", "B2.module").pathString),
                "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B2/include"]),
            ])
        )
        let projectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                targetB1,
                targetB2,
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectAPath: projectA,
                    projectBPath: projectB,
                ],
                dependencies: [
                    .target(name: targetA.name, path: projectAPath): [
                        .target(name: targetB1.name, path: projectBPath),
                    ],
                    .target(name: targetB1.name, path: projectBPath): [
                        .target(name: targetB2.name, path: projectBPath),
                    ],
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then
        let combinedModuleMapPathA = projectAPath.appending(components: "Derived", "ModuleMaps", "A-deps.modulemap")
        let combinedModuleMapPathB1 = projectBPath.appending(components: "Derived", "ModuleMaps", "B1-deps.modulemap")

        let mappedTargetA = Target.test(
            name: "A",
            settings: .test(base: [
                "OTHER_CFLAGS": .array([
                    "Other",
                    "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
                ]),
                "OTHER_SWIFT_FLAGS": .array([
                    "Other",
                    "-Xcc",
                    "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
                ]),
                "HEADER_SEARCH_PATHS": .array(["$(inherited)", "$(SRCROOT)/../B/B1/include", "$(SRCROOT)/../B/B2/include"]),
            ]),
            dependencies: [
                .project(target: "B1", path: projectBPath),
            ]
        )
        let mappedProjectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                mappedTargetA,
            ]
        )

        let mappedTargetB1 = Target.test(
            name: "B1",
            settings: .test(base: [
                "OTHER_CFLAGS": .array([
                    "$(inherited)",
                    "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/B1-deps.modulemap",
                ]),
                "OTHER_SWIFT_FLAGS": .array([
                    "$(inherited)",
                    "-Xcc",
                    "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/B1-deps.modulemap",
                ]),
                "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B1/include", "$(SRCROOT)/B2/include"]),
            ]),
            dependencies: [
                .target(name: "B2"),
            ]
        )
        let mappedTargetB2 = Target.test(
            name: "B2",
            settings: .test(
                base: [
                    "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B2/include"]),
                ]
            )
        )
        let mappedProjectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                mappedTargetB1,
                mappedTargetB2,
            ]
        )

        XCTAssertBetterEqual(
            Graph.test(
                workspace: workspace,
                projects: [
                    projectAPath: mappedProjectA,
                    projectBPath: mappedProjectB,
                ],
                dependencies: [
                    .target(name: targetA.name, path: projectAPath): [
                        .target(name: targetB1.name, path: projectBPath),
                    ],
                    .target(name: targetB1.name, path: projectBPath): [
                        .target(name: targetB2.name, path: projectBPath),
                    ],
                ]
            ),
            gotGraph
        )

        // Verify side effects: combined module map files for A and B1
        let sideEffectPaths = gotSideEffects.compactMap { sideEffect -> AbsolutePath? in
            if case let .file(descriptor) = sideEffect { return descriptor.path }
            return nil
        }.sorted()
        XCTAssertEqual(sideEffectPaths, [combinedModuleMapPathA, combinedModuleMapPathB1].sorted())

        // Verify combined module map content for target A (has B1 and B2 module maps)
        let sideEffectA = gotSideEffects.first { sideEffect in
            if case let .file(descriptor) = sideEffect { return descriptor.path == combinedModuleMapPathA }
            return false
        }
        if case let .file(descriptorA) = sideEffectA {
            let contentA = String(data: descriptorA.contents!, encoding: .utf8)!
            let b1ModuleMapPath = projectBPath.appending(components: "B1", "B1.module").pathString
            let b2ModuleMapPath = projectBPath.appending(components: "B2", "B2.module").pathString
            XCTAssertTrue(contentA.contains("extern module B1 \"\(b1ModuleMapPath)\""))
            XCTAssertTrue(contentA.contains("extern module B2 \"\(b2ModuleMapPath)\""))
        } else {
            XCTFail("Expected file side effect for target A combined module map")
        }

        // Verify combined module map content for target B1 (has only B2 module map)
        let sideEffectB1 = gotSideEffects.first { sideEffect in
            if case let .file(descriptor) = sideEffect { return descriptor.path == combinedModuleMapPathB1 }
            return false
        }
        if case let .file(descriptorB1) = sideEffectB1 {
            let contentB1 = String(data: descriptorB1.contents!, encoding: .utf8)!
            let b2ModuleMapPath = projectBPath.appending(components: "B2", "B2.module").pathString
            XCTAssertEqual(contentB1, "extern module B2 \"\(b2ModuleMapPath)\"\n")
        } else {
            XCTFail("Expected file side effect for target B1 combined module map")
        }
    }

    func test_maps_modulemap_build_flag_to_target_with_empty_settings() throws {
        // Given
        let workspace = Workspace.test()
        let projectAPath = try temporaryPath().appending(component: "A")
        let projectBPath = try temporaryPath().appending(component: "B")

        let targetA = Target.test(
            name: "A",
            settings: nil,
            dependencies: [
                .project(target: "B", path: projectBPath),
            ]
        )
        let projectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                targetA,
            ]
        )

        let targetB = Target.test(
            name: "B",
            settings: .test(base: [
                "MODULEMAP_FILE": .string(projectBPath.appending(components: "B", "B.module").pathString),
                "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B/include"]),
            ])
        )
        let projectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                targetB,
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectAPath: projectA,
                    projectBPath: projectB,
                ],
                dependencies: [
                    .target(name: targetA.name, path: projectAPath): [
                        .target(name: targetB.name, path: projectBPath),
                    ],
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then
        let combinedModuleMapPath = projectAPath.appending(components: "Derived", "ModuleMaps", "A-deps.modulemap")

        let mappedTargetA = Target.test(
            name: "A",
            settings: Settings(
                base: [
                    "OTHER_CFLAGS": .array([
                        "$(inherited)",
                        "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
                    ]),
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-Xcc",
                        "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
                    ]),
                    "HEADER_SEARCH_PATHS": .array(["$(inherited)", "$(SRCROOT)/../B/B/include"]),
                ],
                configurations: [:],
                defaultSettings: .recommended
            ),
            dependencies: [
                .project(target: "B", path: projectBPath),
            ]
        )
        let mappedProjectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                mappedTargetA,
            ]
        )

        let mappedTargetB = Target.test(
            name: "B",
            settings: .test(
                base: [
                    "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B/include"]),
                ]
            )
        )
        let mappedProjectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                mappedTargetB,
            ]
        )

        XCTAssertBetterEqual(
            Graph.test(
                workspace: workspace,
                projects: [
                    projectAPath: mappedProjectA,
                    projectBPath: mappedProjectB,
                ],
                dependencies: [
                    .target(name: projectA.name, path: projectAPath): [
                        .target(name: projectB.name, path: projectBPath),
                    ],
                ]
            ),
            gotGraph
        )

        // Verify side effect: combined module map for A
        XCTAssertEqual(gotSideEffects.count, 1)
        if case let .file(descriptor) = gotSideEffects.first {
            XCTAssertEqual(descriptor.path, combinedModuleMapPath)
            let content = String(data: descriptor.contents!, encoding: .utf8)!
            let bModuleMapPath = projectBPath.appending(components: "B", "B.module").pathString
            XCTAssertEqual(content, "extern module B \"\(bModuleMapPath)\"\n")
        } else {
            XCTFail("Expected file side effect for combined module map")
        }
    }

    func test_maps_modulemap_flags_to_configurations_that_override_other_swift_flags() throws {
        // Given
        let workspace = Workspace.test()
        let projectAPath = try temporaryPath().appending(component: "A")
        let projectBPath = try temporaryPath().appending(component: "B")

        let debugConfig = BuildConfiguration(name: "Debug", variant: .debug)
        let releaseConfig = BuildConfiguration(name: "Release", variant: .release)

        let targetA = Target.test(
            name: "A",
            settings: .test(
                base: [
                    "OTHER_SWIFT_FLAGS": "Other",
                    "OTHER_CFLAGS": ["Other"],
                ],
                configurations: [
                    debugConfig: Configuration(
                        settings: [
                            "OTHER_SWIFT_FLAGS": "-D DEBUG -D FEATURE",
                            "OTHER_CFLAGS": "-DDEBUG",
                        ],
                        xcconfig: nil
                    ),
                    releaseConfig: Configuration(
                        settings: [:],
                        xcconfig: nil
                    ),
                ]
            ),
            dependencies: [
                .project(target: "B", path: projectBPath),
            ]
        )
        let projectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [targetA]
        )

        let targetB = Target.test(
            name: "B",
            settings: .test(base: [
                "MODULEMAP_FILE": .string(projectBPath.appending(components: "B", "B.module").pathString),
                "HEADER_SEARCH_PATHS": .array(["$(SRCROOT)/B/include"]),
            ])
        )
        let projectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [targetB]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectAPath: projectA,
                    projectBPath: projectB,
                ],
                dependencies: [
                    .target(name: targetA.name, path: projectAPath): [
                        .target(name: targetB.name, path: projectBPath),
                    ],
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then
        let gotTargetA = try XCTUnwrap(gotGraph.projects[projectAPath]?.targets["A"])

        // Base settings should have the combined module map flag
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"],
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_CFLAGS"],
            .array([
                "Other",
                "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
            ])
        )

        // Debug configuration overrides OTHER_SWIFT_FLAGS and OTHER_CFLAGS, so it should also get the flag
        let debugConfiguration = try XCTUnwrap(gotTargetA.settings?.configurations[debugConfig] as? Configuration)
        XCTAssertBetterEqual(
            debugConfiguration.settings["OTHER_SWIFT_FLAGS"],
            .array([
                "-D",
                "DEBUG",
                "-D",
                "FEATURE",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            debugConfiguration.settings["OTHER_CFLAGS"],
            .array([
                "-DDEBUG",
                "-fmodule-map-file=$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap",
            ])
        )

        // Release configuration does not override these keys, so it should remain unchanged
        let releaseConfiguration = try XCTUnwrap(
            gotTargetA.settings?.configurations[releaseConfig] as? Configuration
        )
        XCTAssertNil(releaseConfiguration.settings["OTHER_SWIFT_FLAGS"])
        XCTAssertNil(releaseConfiguration.settings["OTHER_CFLAGS"])

        // Verify side effect
        XCTAssertEqual(gotSideEffects.count, 1)
        if case let .file(descriptor) = gotSideEffects.first {
            let combinedModuleMapPath = projectAPath.appending(components: "Derived", "ModuleMaps", "A-deps.modulemap")
            XCTAssertEqual(descriptor.path, combinedModuleMapPath)
        } else {
            XCTFail("Expected file side effect for combined module map")
        }
    }

    func test_external_spm_project_anchors_tuist_derived_paths_on_project_dir() throws {
        // Given — mirrors how Tuist lays out external SwiftPM projects after
        // `ExternalDependencyPathWorkspaceMapper` runs: the SwiftPM checkout sits at
        // `<scratch>/checkouts/<Pkg>/` (and is what `$(SRCROOT)` resolves to at build time, due to
        // an override applied by that mapper), while the generated `.xcodeproj` lives under
        // `<scratch>/tuist-derived/Projects/<Pkg>/` (and is what `$(PROJECT_DIR)` resolves to).
        // Shared module maps and header search paths live under `<scratch>/tuist-derived/ModuleMaps/`.
        //
        // The historical emission `$(SRCROOT)/../../tuist-derived/...` traverses `<scratch>/checkouts/`
        // via `..`, which fails on Xcode 26.5+ when that directory is replaced by a symlink (e.g.
        // Namespace's `nscloud-cache-action`). Anchoring on `$(PROJECT_DIR)` keeps the traversal
        // entirely inside `tuist-derived/`, never touching the symlinked subtree.
        let workspace = Workspace.test()
        let scratch = try temporaryPath().appending(component: ".build")
        let projectAPath = scratch.appending(components: "checkouts", "A")
        let projectBPath = scratch.appending(components: "checkouts", "B")
        let projectAXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "A", "A.xcodeproj")
        let projectBXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "B", "B.xcodeproj")
        let derivedRoot = scratch.appending(component: "tuist-derived")
        let moduleMapPath = derivedRoot.appending(components: "ModuleMaps", "B", "B.modulemap")
        let headerSearchPath = derivedRoot.appending(components: "ModuleMaps", "B")

        let targetA = Target.test(
            name: "A",
            settings: .test(base: [
                "OTHER_SWIFT_FLAGS": "Other",
                "OTHER_CFLAGS": ["Other"],
            ]),
            dependencies: [
                .project(target: "B", path: projectBPath),
            ]
        )
        let projectA = Project.test(
            path: projectAPath,
            xcodeProjPath: projectAXcodeProj,
            name: "A",
            targets: [targetA],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )

        let targetB = Target.test(
            name: "B",
            settings: .test(base: [
                "MODULEMAP_FILE": .string(moduleMapPath.pathString),
                "HEADER_SEARCH_PATHS": .array([headerSearchPath.pathString]),
            ])
        )
        let projectB = Project.test(
            path: projectBPath,
            xcodeProjPath: projectBXcodeProj,
            name: "B",
            targets: [targetB],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectAPath: projectA,
                    projectBPath: projectB,
                ],
                dependencies: [
                    .target(name: targetA.name, path: projectAPath): [
                        .target(name: targetB.name, path: projectBPath),
                    ],
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then — `$(PROJECT_DIR)` for project A resolves to `<scratch>/tuist-derived/Projects/A/`
        // at build time, so `$(PROJECT_DIR)/../../ModuleMaps/A-deps.modulemap` resolves to
        // `<scratch>/tuist-derived/ModuleMaps/A-deps.modulemap` without traversing
        // `<scratch>/checkouts/`.
        let gotTargetA = try XCTUnwrap(gotGraph.projects[projectAPath]?.targets["A"])
        let combinedModuleMapPath = derivedRoot.appending(components: "ModuleMaps", "A-deps.modulemap")

        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"],
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=$(PROJECT_DIR)/../../ModuleMaps/A-deps.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_CFLAGS"],
            .array([
                "Other",
                "-fmodule-map-file=$(PROJECT_DIR)/../../ModuleMaps/A-deps.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["HEADER_SEARCH_PATHS"],
            .array([
                "$(inherited)",
                "$(PROJECT_DIR)/../../ModuleMaps/B",
            ])
        )

        // No `..` segments through `.build/checkouts/` in any flag — that's the whole point.
        let allFlags = gotTargetA.settings?.base.values.compactMap { value -> String? in
            if case let .array(items) = value { return items.joined(separator: " ") }
            return nil
        }.joined(separator: " ") ?? ""
        XCTAssertFalse(
            allFlags.contains("$(SRCROOT)/../../tuist-derived"),
            "module-map paths under tuist-derived must not embed `..` segments through `.build/checkouts`"
        )

        XCTAssertEqual(gotSideEffects.count, 1)
        if case let .file(descriptor) = gotSideEffects.first {
            XCTAssertEqual(descriptor.path, combinedModuleMapPath)
            let content = try XCTUnwrap(String(data: try XCTUnwrap(descriptor.contents), encoding: .utf8))
            XCTAssertEqual(content, "extern module B \"\(moduleMapPath.pathString)\"\n")
        } else {
            XCTFail("Expected file side effect for combined module map")
        }
    }
}
