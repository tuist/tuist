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
                underlying: ToolError.message(
                    "error: Could not find Package.swift in this directory or any of its parent directories."
                )
            )

            #expect(
                error.description == "expected a Package.swift in \(packageDir.path), but found none"
            )
        }
    }

    @Test
    func dumpFailureDistinguishesAMissingDirectoryFromAMissingManifest() async throws {
        try await withTemporaryDirectory { directory in
            let packageDir = directory.appendingPathComponent("Absent")

            let error = await ManifestLoader.dumpFailure(
                packageDir: packageDir, underlying: ToolError.message("chdir error")
            )

            #expect(
                error.description
                    == "expected a package in \(packageDir.path), but the directory does not exist"
            )
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

            #expect(
                error.description
                    == "failed to load the package manifest in \(packageDir.path): compile error"
            )
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
                #expect(description.contains("but found none"))
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
