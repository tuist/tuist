import Foundation
import Testing
@testable import SwifterPMCore

struct ManifestTests {
    @Test
    func parseManifestDependenciesReadsSourceControlAndRegistryDependencies() throws {
        let manifest: [String: Any] = [
            "dependencies": [
                [
                    "sourceControl": [
                        [
                            "identity": "Foo",
                            "location": [
                                "remote": [
                                    ["urlString": "https://github.com/example/foo.git"]
                                ]
                            ],
                            "requirement": [
                                "range": [
                                    [
                                        "lowerBound": "1.0.0",
                                        "upperBound": "2.0.0",
                                    ]
                                ]
                            ],
                        ]
                    ]
                ],
                [
                    "registry": [
                        [
                            "identity": "example.bar",
                            "requirement": [
                                "exact": ["3.4.5"]
                            ],
                        ]
                    ]
                ],
            ]
        ]

        let dependencies = try ManifestParser.dependencies(manifest)

        #expect(dependencies.count == 2)
        #expect(dependencies[0].identity == "Foo")
        #expect(dependencies[0].kind == .sourceControl)
        #expect(dependencies[0].location == "https://github.com/example/foo.git")
        guard case .range(let lower, let upper) = dependencies[0].requirement else {
            Issue.record("expected range requirement")
            return
        }
        #expect(lower.description == "1.0.0")
        #expect(upper.description == "2.0.0")

        #expect(dependencies[1].identity == "example.bar")
        #expect(dependencies[1].kind == .registry)
        guard case .exact(let version) = dependencies[1].requirement else {
            Issue.record("expected exact requirement")
            return
        }
        #expect(version.description == "3.4.5")
    }

    @Test
    func parseRequiredManifestDependenciesKeepsOnlyReachableDependencies() throws {
        let manifest: [String: Any] = [
            "products": [
                [
                    "name": "App",
                    "targets": ["App"],
                ]
            ],
            "targets": [
                [
                    "name": "App",
                    "dependencies": [
                        ["product": ["FooProduct", "Foo"]]
                    ],
                ]
            ],
            "dependencies": [
                [
                    "sourceControl": [
                        sourceDependency(identity: "Foo"),
                        sourceDependency(identity: "Unused"),
                    ]
                ]
            ],
        ]

        let dependencies = try ManifestParser.requiredDependencies(manifest)

        #expect(dependencies.map(\.identity) == ["Foo"])
    }

    @Test
    func parseRequiredManifestDependenciesIgnoresTestOnlyDependencies() throws {
        let manifest: [String: Any] = [
            "products": [
                [
                    "name": "Library",
                    "targets": ["Library"],
                ]
            ],
            "targets": [
                [
                    "name": "Library",
                    "dependencies": [],
                ],
                [
                    "name": "LibraryTests",
                    "type": "test",
                    "dependencies": [
                        ["product": ["Nimble", "Nimble"]]
                    ],
                ],
            ],
            "dependencies": [
                [
                    "sourceControl": [
                        sourceDependency(identity: "Nimble")
                    ]
                ]
            ],
        ]

        let dependencies = try ManifestParser.requiredDependencies(manifest)

        #expect(dependencies.isEmpty)
    }

    @Test
    func parseRequiredManifestDependenciesIgnoresDependenciesUnusedByProducts() throws {
        let manifest: [String: Any] = [
            "products": [
                [
                    "name": "Library",
                    "targets": ["Library"],
                ]
            ],
            "targets": [
                [
                    "name": "Library",
                    "dependencies": [
                        ["product": ["FooProduct", "Foo"]]
                    ],
                ]
            ],
            "dependencies": [
                [
                    "sourceControl": [
                        sourceDependency(identity: "Foo"),
                        sourceDependency(identity: "Unused"),
                    ]
                ]
            ],
        ]

        let dependencies = try ManifestParser.requiredDependencies(manifest)

        #expect(dependencies.map(\.identity) == ["Foo"])
    }

    @Test
    func parseRequiredManifestDependenciesFollowsExplicitTargetDependencies() throws {
        let manifest: [String: Any] = [
            "products": [
                [
                    "name": "Library",
                    "targets": ["LibraryTarget"],
                ]
            ],
            "targets": [
                [
                    "name": "LibraryTarget",
                    "dependencies": [
                        ["target": ["ImplementationTarget", nil]]
                    ],
                ],
                [
                    "name": "ImplementationTarget",
                    "dependencies": [
                        ["product": ["Abseil", "abseil-cpp-binary", nil, nil]]
                    ],
                ],
            ],
            "dependencies": [
                [
                    "sourceControl": [
                        sourceDependency(identity: "abseil-cpp-binary"),
                        sourceDependency(identity: "Unused"),
                    ]
                ]
            ],
        ]

        let dependencies = try ManifestParser.requiredDependencies(manifest)

        #expect(dependencies.map(\.identity) == ["abseil-cpp-binary"])
    }

    @Test
    func parseRequiredManifestDependenciesMatchesPackageAliases() throws {
        let sentry = sourceDependency(identity: "sentry-cocoa").merging(
            ["nameForTargetDependencyResolutionOnly": "Sentry"],
            uniquingKeysWith: { _, new in new }
        )
        let manifest: [String: Any] = [
            "products": [
                [
                    "name": "Library",
                    "targets": ["Library"],
                ]
            ],
            "targets": [
                [
                    "name": "Library",
                    "dependencies": [
                        ["byName": ["Sentry", nil]]
                    ],
                ]
            ],
            "dependencies": [
                [
                    "sourceControl": [
                        sentry,
                        sourceDependency(identity: "Unused"),
                    ]
                ]
            ],
        ]

        let dependencies = try ManifestParser.requiredDependencies(manifest)

        #expect(dependencies.map(\.identity) == ["sentry-cocoa"])
    }

    @Test
    func parseManifestFileSystemDependenciesUsesFallbackName() throws {
        let manifest: [String: Any] = [
            "dependencies": [
                [
                    "fileSystem": [
                        [
                            "identity": "local-dependency",
                            "path": "../LocalDependency",
                        ],
                        [
                            "identity": "named-dependency",
                            "nameForTargetDependencyResolutionOnly": "Named",
                            "path": "../Named",
                        ],
                    ]
                ]
            ]
        ]

        let dependencies = try ManifestParser.fileSystemDependencies(manifest)

        #expect(dependencies.count == 2)
        #expect(dependencies[0].identity == "local-dependency")
        #expect(dependencies[0].name == "local-dependency")
        #expect(dependencies[1].identity == "named-dependency")
        #expect(dependencies[1].name == "Named")
    }

    @Test
    func manifestDumpCacheLivesUnderBuildDirectory() {
        let packageDir = URL(fileURLWithPath: "/tmp/Package")

        #expect(
            ManifestLoader.cacheFilePath(packageDir: packageDir).path
                == "/tmp/Package/.build/swifterpm/manifests/package.json")
    }

    @Test
    func dumpFailureNamesTheDirectoryMissingAManifest() async throws {
        try await withTemporaryDirectory { directory in
            let packageDir = directory.appendingPathComponent("Empty")
            try await fileSystem.makeDirectory(
                at: packageDir.absolutePath, options: [.createTargetParentDirectories])

            let error = await ManifestLoader.dumpFailure(
                packageDir: packageDir,
                underlying: ToolError.message("could not find Package.swift")
            )

            #expect(
                error.description
                    == "no Package.swift in \(packageDir.path): could not find Package.swift")
        }
    }

    @Test
    func dumpFailureDistinguishesAnUnreadableDirectoryFromAMissingManifest() async throws {
        try await withTemporaryDirectory { directory in
            let packageDir = directory.appendingPathComponent("Absent")

            let error = await ManifestLoader.dumpFailure(
                packageDir: packageDir, underlying: ToolError.message("chdir error")
            )

            #expect(error.description == "could not read \(packageDir.path): chdir error")
        }
    }

    @Test
    func dumpFailureKeepsTheUnderlyingErrorWhenTheManifestExists() async throws {
        try await withTemporaryDirectory { directory in
            let packageDir = directory.appendingPathComponent("Broken")
            try await writeMinimalPackageManifest(at: packageDir, name: "Broken")

            let error = await ManifestLoader.dumpFailure(
                packageDir: packageDir, underlying: ToolError.message("compile error")
            )

            #expect(error.description == "\(packageDir.path): compile error")
        }
    }

    @Test
    func dumpFailureKeepsTheUnderlyingErrorWhenTheProbeCannotAnswer() async throws {
        try await withTemporaryDirectory { directory in
            // A package the probe cannot examine: the parent denies traversal, so `exists`
            // cannot distinguish "absent" from "unreadable". The classification may be wrong;
            // the underlying error must survive it either way.
            let locked = directory.appendingPathComponent("locked")
            let packageDir = locked.appendingPathComponent("Feature")
            try await writeMinimalPackageManifest(at: packageDir, name: "Feature")
            _ = try await SystemProcess.run("/bin/chmod", ["000", locked.path])

            let error = await ManifestLoader.dumpFailure(
                packageDir: packageDir, underlying: ToolError.message("permission denied")
            )

            _ = try await SystemProcess.run("/bin/chmod", ["755", locked.path])

            #expect(error.description.hasSuffix(": permission denied"))
            #expect(error.description.contains(packageDir.path))
        }
    }

    @Test
    func localPackageManifestFailureNamesTheDeclaringPackageAndPath() async throws {
        try await withTemporaryDirectory { directory in
            let rootPackageDir = directory.appendingPathComponent("Root")
            try await writeMinimalPackageManifest(at: rootPackageDir, name: "Root")
            // The declared directory exists but holds no manifest: the shape SwiftPM reports
            // as a bare "Could not find Package.swift ..." with no mention of the dependency.
            let localPackageDir = directory.appendingPathComponent("Packages/Feature")
            try await fileSystem.makeDirectory(
                at: localPackageDir.absolutePath, options: [.createTargetParentDirectories])

            let rootManifest: [String: Any] = [
                "dependencies": [
                    ["fileSystem": [["identity": "feature", "path": localPackageDir.path]]]
                ]
            ]

            do {
                _ = try await ManifestFileSystemDependencyGraph.collect(
                    rootPackageDir: rootPackageDir,
                    rootManifest: rootManifest,
                    disableSandbox: true
                )
                Issue.record("expected the local package manifest to fail to load")
            } catch {
                let description = "\(error)"
                #expect(description.contains("the local package feature"))
                #expect(description.contains("declared as \"\(localPackageDir.path)\""))
                #expect(description.contains(rootPackageDir.path))
                #expect(description.contains("no Package.swift in"))
            }
        }
    }

    @Test
    func localPackageWithoutAManifestDoesNotAdoptAnAncestorPackage() async throws {
        try await withTemporaryDirectory { directory in
            // `swift package dump-package` resolves the package root by walking up from its
            // working directory, and `--package-path` walks up too, so a local dependency
            // pointing at a manifest-less directory underneath another package would dump
            // that ancestor's manifest under this dependency's identity: a silently wrong
            // graph in place of an error.
            try await writeMinimalPackageManifest(at: directory, name: "Ancestor")
            let rootPackageDir = directory.appendingPathComponent("Root")
            try await writeMinimalPackageManifest(at: rootPackageDir, name: "Root")
            let localPackageDir = directory.appendingPathComponent("Packages/Feature")
            try await fileSystem.makeDirectory(
                at: localPackageDir.absolutePath, options: [.createTargetParentDirectories])

            let rootManifest: [String: Any] = [
                "dependencies": [
                    ["fileSystem": [["identity": "feature", "path": localPackageDir.path]]]
                ]
            ]

            do {
                let packages = try await ManifestFileSystemDependencyGraph.collect(
                    rootPackageDir: rootPackageDir,
                    rootManifest: rootManifest,
                    disableSandbox: true
                )
                Issue.record(
                    """
                    expected the local package manifest to fail to load, loaded \
                    \(packages.compactMap { ManifestParser.packageName($0.manifest) }) instead
                    """
                )
            } catch {
                #expect("\(error)".contains("no Package.swift in"))
            }
        }
    }

    @Test
    func dumpingASubdirectoryOfAPackageDoesNotStandInForTheEnclosingPackage() async throws {
        try await withTemporaryDirectory { directory in
            // Root resolution runs through the same dump and defaults to the working
            // directory, so the walk-up let a subdirectory stand in for its own package.
            // It never carried a run to completion (`originHash` reads the manifest at that
            // same directory a step later, and fails), so what the gate removes is a dump of
            // one package announced as another, not a working invocation.
            try await writeMinimalPackageManifest(at: directory, name: "Root")
            let subdirectory = directory.appendingPathComponent("Sources/Root")
            try await fileSystem.makeDirectory(
                at: subdirectory.absolutePath, options: [.createTargetParentDirectories])

            do {
                let manifest = try await ManifestLoader.dumpPackage(
                    packageDir: subdirectory, disableSandbox: true
                )
                Issue.record(
                    """
                    expected the dump to fail, loaded \
                    \(ManifestParser.packageName(manifest) ?? "an unnamed package") instead
                    """
                )
            } catch {
                #expect("\(error)" == "no Package.swift in \(subdirectory.path)")
            }
        }
    }

    @Test
    func localPackageManifestFailureNamesWhereTheDeclaredPathResolvesTo() async throws {
        try await withTemporaryDirectory { directory in
            let rootPackageDir = directory.appendingPathComponent("Root")
            try await writeMinimalPackageManifest(at: rootPackageDir, name: "Root")
            let resolvedDir = directory.appendingPathComponent("Elsewhere")
            try await fileSystem.makeDirectory(
                at: resolvedDir.absolutePath, options: [.createTargetParentDirectories])
            let declaredDir = directory.appendingPathComponent("Packages/Feature")
            try await fileSystem.makeDirectory(
                at: declaredDir.deletingLastPathComponent().absolutePath,
                options: [.createTargetParentDirectories]
            )
            try await fileSystem.createSymbolicLink(
                from: declaredDir.absolutePath, to: resolvedDir.absolutePath)

            let rootManifest: [String: Any] = [
                "dependencies": [
                    ["fileSystem": [["identity": "feature", "path": declaredDir.path]]]
                ]
            ]

            do {
                _ = try await ManifestFileSystemDependencyGraph.collect(
                    rootPackageDir: rootPackageDir,
                    rootManifest: rootManifest,
                    disableSandbox: true
                )
                Issue.record("expected the local package manifest to fail to load")
            } catch {
                // The declared path and the directory the failure names are different
                // directories, and only the redirect explains why: without it the sentence
                // reads as if swifterpm looked in a place nobody declared.
                let description = "\(error)"
                #expect(description.contains("declared as \"\(declaredDir.path)\""))
                #expect(
                    description.contains(
                        "resolves to \(PathCanonicalizer.realpath(resolvedDir).path)"))
            }
        }
    }

    @Test
    func versionRangeMatchesExactAndOpenRanges() throws {
        let exact = try #require(ManifestParser.versionRange(for: .exact(SemVer("1.2.3"))))
        #expect(try exact.contains(SemVer("1.2.3")))
        #expect(try !exact.contains(SemVer("1.2.4")))

        let range = try #require(
            ManifestParser.versionRange(for: .range(lower: SemVer("1.0.0"), upper: SemVer("2.0.0")))
        )
        #expect(try range.contains(SemVer("1.5.0")))
        #expect(try !range.contains(SemVer("2.0.0")))
    }

    private func sourceDependency(identity: String) -> [String: Any] {
        [
            "identity": identity,
            "location": [
                "remote": [
                    ["urlString": "https://github.com/example/\(identity).git"]
                ]
            ],
            "requirement": [
                "range": [
                    [
                        "lowerBound": "1.0.0",
                        "upperBound": "2.0.0",
                    ]
                ]
            ],
        ]
    }
}
