import TuistCore
import TuistGenerator
import XcodeGraph
import XCTest

@testable import TuistTesting

// swiftlint:disable:next type_body_length
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
        let mappedTargetA = Target.test(
            name: "A",
            settings: .test(base: [
                "OTHER_CFLAGS": .array([
                    "Other",
                    "-fmodule-map-file=$(SRCROOT)/../B/B1/B1.module",
                    "-fmodule-map-file=$(SRCROOT)/../B/B2/B2.module",
                ]),
                "OTHER_SWIFT_FLAGS": .array([
                    "Other",
                    "-Xcc",
                    "-fmodule-map-file=$(SRCROOT)/../B/B1/B1.module",
                    "-Xcc",
                    "-fmodule-map-file=$(SRCROOT)/../B/B2/B2.module",
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
                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-map-file=$(SRCROOT)/B2/B2.module"]),
                "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-Xcc", "-fmodule-map-file=$(SRCROOT)/B2/B2.module"]),
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
        XCTAssertEqual(gotSideEffects, [])
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
        let mappedTargetA = Target.test(
            name: "A",
            settings: Settings(
                base: [
                    "OTHER_CFLAGS": .array([
                        "$(inherited)",
                        "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
                    ]),
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-Xcc",
                        "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
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
        XCTAssertEqual(gotSideEffects, [])
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

        // Base settings should have the module map flags
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"],
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_CFLAGS"],
            .array([
                "Other",
                "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
            ])
        )

        // Debug configuration overrides OTHER_SWIFT_FLAGS and OTHER_CFLAGS, so it should also get the flags
        let debugConfiguration = try XCTUnwrap(gotTargetA.settings?.configurations[debugConfig] as? Configuration)
        XCTAssertBetterEqual(
            debugConfiguration.settings["OTHER_SWIFT_FLAGS"],
            .array([
                "-D",
                "DEBUG",
                "-D",
                "FEATURE",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
            ])
        )
        XCTAssertBetterEqual(
            debugConfiguration.settings["OTHER_CFLAGS"],
            .array([
                "-DDEBUG",
                "-fmodule-map-file=$(SRCROOT)/../B/B/B.module",
            ])
        )

        // Release configuration does not override these keys, so it should remain unchanged
        let releaseConfiguration = try XCTUnwrap(
            gotTargetA.settings?.configurations[releaseConfig] as? Configuration
        )
        XCTAssertNil(releaseConfiguration.settings["OTHER_SWIFT_FLAGS"])
        XCTAssertNil(releaseConfiguration.settings["OTHER_CFLAGS"])

        XCTAssertEqual(gotSideEffects, [])
    }

    func test_external_spm_project_anchors_tuist_derived_paths_on_user_defined_setting() throws {
        // Given — mirrors how SwiftPM checkouts are laid out: `<scratch>/checkouts/{A,B}` with shared
        // module maps written under `<scratch>/tuist-derived/ModuleMaps/`. The historical emission
        // `$(SRCROOT)/../../tuist-derived/...` traverses `<scratch>/checkouts/` via `..`, which fails
        // on Xcode 26.5+ when that directory is replaced by a symlink (e.g. by Namespace's
        // `nscloud-cache-action`). The fix anchors these paths on `$(TUIST_SPM_DERIVED_DIR)` instead.
        let workspace = Workspace.test()
        let scratch = try temporaryPath().appending(component: ".build")
        let projectAPath = scratch.appending(components: "checkouts", "A")
        let projectBPath = scratch.appending(components: "checkouts", "B")
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

        // Then
        let gotTargetA = try XCTUnwrap(gotGraph.projects[projectAPath]?.targets["A"])

        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"],
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=$(TUIST_SPM_DERIVED_DIR)/ModuleMaps/B/B.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["OTHER_CFLAGS"],
            .array([
                "Other",
                "-fmodule-map-file=$(TUIST_SPM_DERIVED_DIR)/ModuleMaps/B/B.modulemap",
            ])
        )
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["HEADER_SEARCH_PATHS"],
            .array([
                "$(inherited)",
                "$(TUIST_SPM_DERIVED_DIR)/ModuleMaps/B",
            ])
        )

        // The user-defined setting is defined on the consumer so Xcode can substitute it before
        // invoking clang. The absolute value is kept out of the hash by SettingsContentHasher.
        XCTAssertBetterEqual(
            gotTargetA.settings?.base["TUIST_SPM_DERIVED_DIR"],
            .string(derivedRoot.pathString)
        )

        // Sibling SwiftPM checkouts and non-derived paths still use the historical $(SRCROOT) form,
        // since they don't traverse out of `checkouts/` and therefore don't trip the symlink trap.
        let allFlags = gotTargetA.settings?.base.values.compactMap { value -> String? in
            if case let .array(items) = value { return items.joined(separator: " ") }
            return nil
        }.joined(separator: " ") ?? ""
        XCTAssertFalse(
            allFlags.contains("$(SRCROOT)/../../tuist-derived"),
            "module-map paths under tuist-derived must not embed `..` segments through `.build/checkouts`"
        )

        XCTAssertEqual(gotSideEffects, [])
    }
}
