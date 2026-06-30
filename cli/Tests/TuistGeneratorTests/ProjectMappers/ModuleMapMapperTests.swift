import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistGenerator
import XcodeGraph

@testable import TuistTesting

struct ModuleMapMapperTests {
    private var subject: ModuleMapMapper { ModuleMapMapper() }

    private func temporaryPath() throws -> AbsolutePath {
        try #require(FileSystem.temporaryTestDirectory)
    }

    @Test(.inTemporaryDirectory)
    func maps_modulemap_build_flag_to_setting() throws {
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
                    "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
                ]),
                "OTHER_SWIFT_FLAGS": .array([
                    "Other",
                    "-Xcc",
                    "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
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
                    "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/B1-deps.modulemap\"",
                ]),
                "OTHER_SWIFT_FLAGS": .array([
                    "$(inherited)",
                    "-Xcc",
                    "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/B1-deps.modulemap\"",
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

        #expect(gotGraph ==
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
            )
        )

        // Verify side effects: combined module map files for A and B1
        let b1ModuleMapPath = projectBPath.appending(components: "B1", "B1.module").pathString
        let b2ModuleMapPath = projectBPath.appending(components: "B2", "B2.module").pathString

        #expect(fileSideEffects(from: gotSideEffects).sorted(by: { $0.description < $1.description }) ==
            [
                .file(FileDescriptor(
                    path: combinedModuleMapPathA,
                    contents: Data(
                        "extern module B1 \"\(b1ModuleMapPath)\"\nextern module B2 \"\(b2ModuleMapPath)\"\n".utf8
                    )
                )),
                .file(FileDescriptor(
                    path: combinedModuleMapPathB1,
                    contents: Data("extern module B2 \"\(b2ModuleMapPath)\"\n".utf8)
                )),
            ].sorted(by: { $0.description < $1.description })
        )
    }

    @Test(.inTemporaryDirectory)
    func deletes_stale_generated_dependency_module_maps() throws {
        // Given
        let workspace = Workspace.test()
        let projectAPath = try temporaryPath().appending(component: "A")
        let projectBPath = try temporaryPath().appending(component: "B")
        let moduleMapDirectory = projectAPath.appending(components: "Derived", "ModuleMaps")
        let activeModuleMapPath = moduleMapDirectory.appending(component: "A-deps.modulemap")
        let staleModuleMapPath = moduleMapDirectory.appending(component: "DeletedTarget-deps.modulemap")

        let targetA = Target.test(
            name: "A",
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
        let (_, gotSideEffects, _) = try subject.map(
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
        let cleanupDescriptor = try #require(generatedFilesCleanupDescriptor(in: gotSideEffects))
        #expect(cleanupDescriptor.include == ["*-deps.modulemap"])
        #expect(cleanupDescriptor.directories.contains(moduleMapDirectory))
        #expect(cleanupDescriptor.activeFilesByDirectory[moduleMapDirectory] == Set([activeModuleMapPath]))
        #expect(!(cleanupDescriptor.activeFilesByDirectory[moduleMapDirectory]?.contains(staleModuleMapPath) ?? false))
        #expect(fileSideEffects(from: gotSideEffects).contains { sideEffect in
            guard case let .file(fileDescriptor) = sideEffect else { return false }
            return fileDescriptor.path == activeModuleMapPath && fileDescriptor.state == .present
        })
    }

    @Test(.inTemporaryDirectory)
    func maps_modulemap_build_flag_to_target_with_empty_settings() throws {
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
                        "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
                    ]),
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-Xcc",
                        "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
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

        #expect(gotGraph ==
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
            )
        )

        // Verify side effect: combined module map for A
        let bModuleMapPath = projectBPath.appending(components: "B", "B.module").pathString
        #expect(fileSideEffects(from: gotSideEffects) ==
            [
                .file(FileDescriptor(
                    path: combinedModuleMapPath,
                    contents: Data("extern module B \"\(bModuleMapPath)\"\n".utf8)
                )),
            ]
        )
    }

    @Test(.inTemporaryDirectory)
    func maps_framework_modulemap_to_modulemap_copy_script() throws {
        // Given
        let workspace = Workspace.test()
        let projectPath = try temporaryPath().appending(component: "A")
        let moduleMapPath = projectPath.appending(components: "A", "A.modulemap")
        let target = Target.test(
            name: "A",
            product: .framework,
            settings: .test(base: [
                "MODULEMAP_FILE": .string(moduleMapPath.pathString),
            ])
        )
        let project = Project.test(
            path: projectPath,
            name: "A",
            targets: [target]
        )

        // When
        let (gotGraph, _, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectPath: project,
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then
        let gotTarget = try #require(gotGraph.projects[projectPath]?.targets["A"])
        #expect(gotTarget.settings?.base["MODULEMAP_FILE"] == nil)
        #expect(gotTarget.scripts ==
            [
                TargetScript(
                    name: "Copy Module Map",
                    order: .post,
                    script: .embedded(
                        """
                        set -eu
                        mkdir -p "$TARGET_BUILD_DIR/$WRAPPER_NAME/Modules"
                        install -m 0644 '\(moduleMapPath.pathString)' "$TARGET_BUILD_DIR/$WRAPPER_NAME/Modules/module.modulemap"
                        """
                    ),
                    inputPaths: [moduleMapPath.pathString],
                    outputPaths: ["$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/Modules/module.modulemap"],
                    showEnvVarsInLog: false,
                    basedOnDependencyAnalysis: true
                ),
            ]
        )
    }

    @Test(.inTemporaryDirectory)
    func removes_static_framework_modulemap_without_copy_script() throws {
        // Given
        let workspace = Workspace.test()
        let projectPath = try temporaryPath().appending(component: "A")
        let moduleMapPath = projectPath.appending(components: "A", "A.modulemap")
        let target = Target.test(
            name: "A",
            product: .staticFramework,
            settings: .test(base: [
                "MODULEMAP_FILE": .string(moduleMapPath.pathString),
            ])
        )
        let project = Project.test(
            path: projectPath,
            name: "A",
            targets: [target]
        )

        // When
        let (gotGraph, _, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectPath: project,
                ]
            ),
            environment: MapperEnvironment()
        )

        // Then
        let gotTarget = try #require(gotGraph.projects[projectPath]?.targets["A"])
        #expect(gotTarget.settings?.base["MODULEMAP_FILE"] == nil)
        #expect(gotTarget.scripts.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func maps_modulemap_flags_to_configurations_that_override_other_swift_flags() throws {
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
        let gotTargetA = try #require(gotGraph.projects[projectAPath]?.targets["A"])

        // Base settings should have the combined module map flag
        #expect(gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"] ==
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
            ])
        )
        #expect(gotTargetA.settings?.base["OTHER_CFLAGS"] ==
            .array([
                "Other",
                "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
            ])
        )

        // Debug configuration overrides OTHER_SWIFT_FLAGS and OTHER_CFLAGS, so it should also get the flag
        let debugConfiguration = try #require(gotTargetA.settings?.configurations[debugConfig] as? Configuration)
        #expect(debugConfiguration.settings["OTHER_SWIFT_FLAGS"] ==
            .array([
                "-D",
                "DEBUG",
                "-D",
                "FEATURE",
                "-Xcc",
                "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
            ])
        )
        #expect(debugConfiguration.settings["OTHER_CFLAGS"] ==
            .array([
                "-DDEBUG",
                "-fmodule-map-file=\"$(SRCROOT)/Derived/ModuleMaps/A-deps.modulemap\"",
            ])
        )

        // Release configuration does not override these keys, so it should remain unchanged
        let releaseConfiguration = try #require(
            gotTargetA.settings?.configurations[releaseConfig] as? Configuration
        )
        #expect(releaseConfiguration.settings["OTHER_SWIFT_FLAGS"] == nil)
        #expect(releaseConfiguration.settings["OTHER_CFLAGS"] == nil)

        // Verify side effect
        let combinedModuleMapPath = projectAPath.appending(components: "Derived", "ModuleMaps", "A-deps.modulemap")
        let bModuleMapPath = projectBPath.appending(components: "B", "B.module").pathString
        #expect(fileSideEffects(from: gotSideEffects) ==
            [
                .file(FileDescriptor(
                    path: combinedModuleMapPath,
                    contents: Data("extern module B \"\(bModuleMapPath)\"\n".utf8)
                )),
            ]
        )
    }

    @Test(.inTemporaryDirectory)
    func external_spm_project_anchors_tuist_derived_paths_on_project_dir() throws {
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
        // at build time, so `$(PROJECT_DIR)/../../ModuleMaps/A/A-deps.modulemap` resolves to
        // `<scratch>/tuist-derived/ModuleMaps/A/A-deps.modulemap` without traversing
        // `<scratch>/checkouts/`. The project-name namespace keeps same-named targets in
        // different SwiftPM packages from clobbering each other's combined module maps.
        let gotTargetA = try #require(gotGraph.projects[projectAPath]?.targets["A"])
        let combinedModuleMapPath = derivedRoot.appending(components: "ModuleMaps", "A", "A-deps.modulemap")

        #expect(gotTargetA.settings?.base["OTHER_SWIFT_FLAGS"] ==
            .array([
                "Other",
                "-Xcc",
                "-fmodule-map-file=\"$(PROJECT_DIR)/../../ModuleMaps/A/A-deps.modulemap\"",
            ])
        )
        #expect(gotTargetA.settings?.base["OTHER_CFLAGS"] ==
            .array([
                "Other",
                "-fmodule-map-file=\"$(PROJECT_DIR)/../../ModuleMaps/A/A-deps.modulemap\"",
            ])
        )
        #expect(gotTargetA.settings?.base["HEADER_SEARCH_PATHS"] ==
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
        #expect(
            !allFlags.contains("$(SRCROOT)/../../tuist-derived"),
            "module-map paths under tuist-derived must not embed `..` segments through `.build/checkouts`"
        )

        let gotFileSideEffects = fileSideEffects(from: gotSideEffects)
        #expect(gotFileSideEffects.count == 1)
        let gotSideEffect = try #require(gotFileSideEffects.first)
        guard case let .file(descriptor) = gotSideEffect else {
            Issue.record("Expected file side effect for combined module map")
            return
        }
        #expect(descriptor.path == combinedModuleMapPath)
        let contents = try #require(descriptor.contents)
        let content = try #require(String(data: contents, encoding: .utf8))
        #expect(content == "extern module B \"\(moduleMapPath.pathString)\"\n")
    }

    @Test(.inTemporaryDirectory)
    func external_spm_projects_with_same_target_name_use_distinct_combined_module_maps() throws {
        let workspace = Workspace.test()
        let scratch = try temporaryPath().appending(component: ".build")
        let derivedRoot = scratch.appending(component: "tuist-derived")

        let packageAPath = scratch.appending(components: "checkouts", "PackageA")
        let packageAXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "PackageA", "PackageA.xcodeproj")
        let depAPath = scratch.appending(components: "checkouts", "DepA")
        let depAXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "DepA", "DepA.xcodeproj")
        let depAModuleMapPath = derivedRoot.appending(components: "ModuleMaps", "DepA", "DepA.modulemap")
        let depAHeaderSearchPath = derivedRoot.appending(components: "ModuleMaps", "DepA")

        let packageBPath = scratch.appending(components: "checkouts", "PackageB")
        let packageBXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "PackageB", "PackageB.xcodeproj")
        let depBPath = scratch.appending(components: "checkouts", "DepB")
        let depBXcodeProj = scratch.appending(components: "tuist-derived", "Projects", "DepB", "DepB.xcodeproj")
        let depBModuleMapPath = derivedRoot.appending(components: "ModuleMaps", "DepB", "DepB.modulemap")
        let depBHeaderSearchPath = derivedRoot.appending(components: "ModuleMaps", "DepB")

        let coreA = Target.test(
            name: "Core",
            settings: .test(base: [
                "OTHER_SWIFT_FLAGS": "Other",
                "OTHER_CFLAGS": ["Other"],
            ]),
            dependencies: [
                .project(target: "DepA", path: depAPath),
            ]
        )
        let packageA = Project.test(
            path: packageAPath,
            xcodeProjPath: packageAXcodeProj,
            name: "PackageA",
            targets: [coreA],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )
        let depA = Project.test(
            path: depAPath,
            xcodeProjPath: depAXcodeProj,
            name: "DepA",
            targets: [
                Target.test(
                    name: "DepA",
                    settings: .test(base: [
                        "MODULEMAP_FILE": .string(depAModuleMapPath.pathString),
                        "HEADER_SEARCH_PATHS": .array([depAHeaderSearchPath.pathString]),
                    ])
                ),
            ],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )

        let coreB = Target.test(
            name: "Core",
            settings: .test(base: [
                "OTHER_SWIFT_FLAGS": "Other",
                "OTHER_CFLAGS": ["Other"],
            ]),
            dependencies: [
                .project(target: "DepB", path: depBPath),
            ]
        )
        let packageB = Project.test(
            path: packageBPath,
            xcodeProjPath: packageBXcodeProj,
            name: "PackageB",
            targets: [coreB],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )
        let depB = Project.test(
            path: depBPath,
            xcodeProjPath: depBXcodeProj,
            name: "DepB",
            targets: [
                Target.test(
                    name: "DepB",
                    settings: .test(base: [
                        "MODULEMAP_FILE": .string(depBModuleMapPath.pathString),
                        "HEADER_SEARCH_PATHS": .array([depBHeaderSearchPath.pathString]),
                    ])
                ),
            ],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratch
        )

        let (gotGraph, gotSideEffects, _) = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    packageAPath: packageA,
                    depAPath: depA,
                    packageBPath: packageB,
                    depBPath: depB,
                ],
                dependencies: [
                    .target(name: coreA.name, path: packageAPath): [
                        .target(name: "DepA", path: depAPath),
                    ],
                    .target(name: coreB.name, path: packageBPath): [
                        .target(name: "DepB", path: depBPath),
                    ],
                ]
            ),
            environment: MapperEnvironment()
        )

        let gotCoreA = try #require(gotGraph.projects[packageAPath]?.targets["Core"])
        #expect(gotCoreA.settings?.base["OTHER_CFLAGS"] ==
            .array([
                "Other",
                "-fmodule-map-file=\"$(PROJECT_DIR)/../../ModuleMaps/PackageA/Core-deps.modulemap\"",
            ])
        )

        let gotCoreB = try #require(gotGraph.projects[packageBPath]?.targets["Core"])
        #expect(gotCoreB.settings?.base["OTHER_CFLAGS"] ==
            .array([
                "Other",
                "-fmodule-map-file=\"$(PROJECT_DIR)/../../ModuleMaps/PackageB/Core-deps.modulemap\"",
            ])
        )

        let sideEffectPaths = gotSideEffects.compactMap { sideEffect -> AbsolutePath? in
            if case let .file(descriptor) = sideEffect { return descriptor.path }
            return nil
        }

        #expect(Set(sideEffectPaths) ==
            Set([
                derivedRoot.appending(components: "ModuleMaps", "PackageA", "Core-deps.modulemap"),
                derivedRoot.appending(components: "ModuleMaps", "PackageB", "Core-deps.modulemap"),
            ])
        )
    }

    @Test(.inTemporaryDirectory)
    func maps_long_dependency_chain_without_recursion() throws {
        // Given
        let workspace = Workspace.test()
        let projectPath = try temporaryPath()
        let nodeCount = 20000
        let targets = (0 ..< nodeCount).map { index in
            Target.test(
                name: "Target\(index)",
                dependencies: index + 1 < nodeCount ? [.target(name: "Target\(index + 1)")] : []
            )
        }
        let project = Project.test(
            path: projectPath,
            name: "Project",
            targets: targets
        )
        let dependencies = Dictionary(
            uniqueKeysWithValues: (0 ..< nodeCount - 1).map { index in
                (
                    GraphDependency.target(name: "Target\(index)", path: projectPath),
                    Set([GraphDependency.target(name: "Target\(index + 1)", path: projectPath)])
                )
            }
        )

        // Then
        _ = try subject.map(
            graph: .test(
                workspace: workspace,
                projects: [
                    projectPath: project,
                ],
                dependencies: dependencies
            ),
            environment: MapperEnvironment()
        )
    }

    private func fileSideEffects(from sideEffects: [SideEffectDescriptor]) -> [SideEffectDescriptor] {
        sideEffects.compactMap { sideEffect in
            guard case .file = sideEffect else { return nil }
            return sideEffect
        }
    }

    private func generatedFilesCleanupDescriptor(
        in sideEffects: [SideEffectDescriptor]
    ) -> GeneratedFilesCleanupDescriptor? {
        sideEffects.compactMap { sideEffect in
            guard case let .generatedFilesCleanup(descriptor) = sideEffect else { return nil }
            return descriptor
        }.first
    }
}
