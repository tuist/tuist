import FileSystem
import Foundation
import Logging
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting
import XcodeGraph

import protocol XcodeGraphMapper.XcodeGraphMapping

@testable import TuistKit

@Suite
struct XcodeBuildTestCommandServiceTests {
    private let fileSystem = FileSystem()
    private let xcodeGraphMapper = MockXcodeGraphMapping()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let configLoader = MockConfigLoading()
    private let cacheStorage = MockCacheStoring()
    private let selectiveTestingGraphHasher = MockSelectiveTestingGraphHashing()
    private let selectiveTestingService = MockSelectiveTestingServicing()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let uniqueIDGenerator = MockUniqueIDGenerating()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let inspectResultBundleService = MockInspectResultBundleServicing()
    private let subject: XcodeBuildTestCommandService
    init() {
        let cacheStorageFactory = MockCacheStorageFactorying()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(cacheStorage)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()
        given(cacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn([])
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(try! AbsolutePath(validating: "/tmp/runs"))
        given(uniqueIDGenerator)
            .uniqueID()
            .willReturn("unique-id")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(try! AbsolutePath(validating: "/tmp/DerivedData"))

        subject = XcodeBuildTestCommandService(
            fileSystem: fileSystem,
            xcodeGraphMapper: xcodeGraphMapper,
            xcodeBuildController: xcodeBuildController,
            configLoader: configLoader,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            uniqueIDGenerator: uniqueIDGenerator,
            cacheStorageFactory: cacheStorageFactory,
            selectiveTestingGraphHasher: selectiveTestingGraphHasher,
            selectiveTestingService: selectiveTestingService,
            inspectResultBundleService: inspectResultBundleService,
            derivedDataLocator: derivedDataLocator
        )
    }

    @Test func throwsErrorWhenSchemeNotFound() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            // Given
            let project: Project = .test(
                schemes: [
                    .test(name: "DifferentScheme"),
                ]
            )
            given(xcodeGraphMapper)
                .map(at: .any)
                .willReturn(
                    .test(
                        projects: [
                            temporaryPath: project,
                        ]
                    )
                )

            // When / Then
            await #expect(throws: XcodeBuildTestCommandServiceError.schemeNotFound("MyScheme")) {
                try await subject.run(passthroughXcodebuildArguments: [
                    "test", "-scheme", "MyScheme",
                ])
            }
        }
    }

    @Test func throwsErrorWhenSchemeNotPassed() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            _ in
            // When / Then
            await #expect(throws: XcodeBuildTestCommandServiceError.schemeNotPassed) {
                try await subject.run(passthroughXcodebuildArguments: ["test"])
            }
        }
    }

    @Test func existsEarlyIfAllTestsAreCached() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            let runMetadataStorage = RunMetadataStorage()
            try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                // Given
                let aUnitTestsTarget: Target = .test(name: "AUnitTests")
                let bUnitTestsTarget: Target = .test(name: "BUnitTests")
                let project: Project = .test(
                    path: temporaryPath,
                    targets: [
                        aUnitTestsTarget,
                        bUnitTestsTarget,
                    ],
                    schemes: [
                        .test(
                            name: "App",
                            testAction: .test(
                                targets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "AUnitTests"
                                        )
                                    ),
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "BUnitTests"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )

                given(xcodeGraphMapper)
                    .map(at: .any)
                    .willReturn(
                        .test(
                            projects: [
                                temporaryPath: project,
                            ]
                        )
                    )

                given(selectiveTestingGraphHasher)
                    .hash(
                        graph: .any,
                        additionalStrings: .any
                    )
                    .willReturn(
                        [
                            GraphTarget(
                                path: project.path,
                                target: aUnitTestsTarget,
                                project: project
                            ): .test(hash: "hash-a-unit-tests"),
                            GraphTarget(
                                path: project.path,
                                target: bUnitTestsTarget,
                                project: project
                            ): .test(hash: "hash-b-unit-tests"),
                        ]
                    )
                given(selectiveTestingService)
                    .cachedTests(
                        testableGraphTargets: .any,
                        selectiveTestingHashes: .any,
                        selectiveTestingCacheItems: .any
                    )
                    .willReturn(
                        [
                            try TestIdentifier(string: "AUnitTests"),
                            try TestIdentifier(string: "BUnitTests"),
                        ]
                    )

                given(cacheStorage)
                    .fetch(.any, cacheCategory: .any)
                    .willReturn(
                        [
                            CacheItem(
                                name: "AUnitTests",
                                hash: "hash-a-unit-tests",
                                source: .local,
                                cacheCategory: .selectiveTests
                            ): temporaryPath,
                            CacheItem(
                                name: "BUnitTests",
                                hash: "hash-b-unit-tests",
                                source: .remote,
                                cacheCategory: .selectiveTests
                            ): temporaryPath,
                        ]
                    )

                // When
                try await subject.run(
                    passthroughXcodebuildArguments: [
                        "test",
                        "-scheme", "App",
                    ]
                )

                // Then
                verify(xcodeBuildController)
                    .run(
                        arguments: .any
                    )
                    .called(0)
                verify(cacheStorage)
                    .store(
                        .any,
                        cacheCategory: .value(.selectiveTests)
                    )
                    .called(0)
                await #expect(
                    runMetadataStorage.selectiveTestingCacheItems == [
                        temporaryPath: [
                            "AUnitTests": CacheItem(
                                name: "AUnitTests",
                                hash: "hash-a-unit-tests",
                                source: .local,
                                cacheCategory: .selectiveTests
                            ),
                            "BUnitTests": CacheItem(
                                name: "BUnitTests",
                                hash: "hash-b-unit-tests",
                                source: .remote,
                                cacheCategory: .selectiveTests
                            ),
                        ],
                    ]
                )
            }
        }
    }

    @Test func skipsCachedTests() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            let runMetadataStorage = RunMetadataStorage()
            try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                // Given
                let aUnitTestsTarget: Target = .test(name: "AUnitTests")
                let bUnitTestsTarget: Target = .test(name: "BUnitTests")
                let project: Project = .test(
                    path: temporaryPath,
                    targets: [
                        aUnitTestsTarget,
                        bUnitTestsTarget,
                    ],
                    schemes: [
                        .test(
                            name: "App",
                            testAction: .test(
                                targets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "AUnitTests"
                                        )
                                    ),
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "BUnitTests"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )

                given(xcodeGraphMapper)
                    .map(at: .any)
                    .willReturn(
                        .test(
                            projects: [
                                temporaryPath: project,
                            ]
                        )
                    )

                given(selectiveTestingGraphHasher)
                    .hash(
                        graph: .any,
                        additionalStrings: .any
                    )
                    .willReturn(
                        [
                            GraphTarget(
                                path: project.path,
                                target: aUnitTestsTarget,
                                project: project
                            ): .test(hash: "hash-a-unit-tests"),
                            GraphTarget(
                                path: project.path,
                                target: bUnitTestsTarget,
                                project: project
                            ): .test(hash: "hash-b-unit-tests"),
                        ]
                    )
                given(selectiveTestingService)
                    .cachedTests(
                        testableGraphTargets: .any,
                        selectiveTestingHashes: .any,
                        selectiveTestingCacheItems: .any
                    )
                    .willReturn(
                        [
                            try TestIdentifier(string: "AUnitTests"),
                        ]
                    )

                given(cacheStorage)
                    .fetch(.any, cacheCategory: .any)
                    .willReturn(
                        [
                            CacheItem(
                                name: "AUnitTests",
                                hash: "hash-a-unit-tests",
                                source: .local,
                                cacheCategory: .selectiveTests
                            ): temporaryPath,
                        ]
                    )

                // When
                try await subject.run(
                    passthroughXcodebuildArguments: [
                        "test",
                        "-scheme", "App",
                    ]
                )

                // Then
                verify(xcodeBuildController)
                    .run(
                        arguments: .value(
                            [
                                "test",
                                "-scheme", "App",
                                "-skip-testing:AUnitTests",
                                "-resultBundlePath", "/tmp/runs/unique-id",
                            ]
                        )
                    )
                    .called(1)
                verify(cacheStorage)
                    .store(
                        .value(
                            [
                                CacheStorableItem(name: "BUnitTests", hash: "hash-b-unit-tests"): [
                                    AbsolutePath
                                ](),
                            ]
                        ),
                        cacheCategory: .value(.selectiveTests)
                    )
                    .called(1)
                await #expect(
                    runMetadataStorage.selectiveTestingCacheItems == [
                        temporaryPath: [
                            "AUnitTests": CacheItem(
                                name: "AUnitTests",
                                hash: "hash-a-unit-tests",
                                source: .local,
                                cacheCategory: .selectiveTests
                            ),
                            "BUnitTests": CacheItem(
                                name: "BUnitTests",
                                hash: "hash-b-unit-tests",
                                source: .miss,
                                cacheCategory: .selectiveTests
                            ),
                        ],
                    ]
                )
            }
        }
    }

    @Test func updatesAnalyicsWhenXcodeBuildFails() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            let runMetadataStorage = RunMetadataStorage()
            await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                // Given
                let aUnitTestsTarget: Target = .test(name: "AUnitTests")
                let project: Project = .test(
                    path: temporaryPath,
                    targets: [
                        aUnitTestsTarget,
                    ],
                    schemes: [
                        .test(
                            name: "App",
                            testAction: .test(
                                targets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "AUnitTests"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )

                given(xcodeGraphMapper)
                    .map(at: .any)
                    .willReturn(
                        .test(
                            projects: [
                                temporaryPath: project,
                            ]
                        )
                    )

                given(selectiveTestingGraphHasher)
                    .hash(
                        graph: .any,
                        additionalStrings: .any
                    )
                    .willReturn(
                        [
                            GraphTarget(
                                path: project.path,
                                target: aUnitTestsTarget,
                                project: project
                            ): .test(hash: "hash-a-unit-tests"),
                        ]
                    )
                given(selectiveTestingService)
                    .cachedTests(
                        testableGraphTargets: .any,
                        selectiveTestingHashes: .any,
                        selectiveTestingCacheItems: .any
                    )
                    .willReturn(
                        []
                    )

                given(cacheStorage)
                    .fetch(.any, cacheCategory: .any)
                    .willReturn(
                        [:]
                    )
                xcodeBuildController.reset()
                given(xcodeBuildController)
                    .run(arguments: .any)
                    .willThrow(TestError("failed"))

                // When
                await #expect(
                    throws: TestError("failed"),
                    performing: {
                        try await subject.run(
                            passthroughXcodebuildArguments: [
                                "test",
                                "-scheme", "App",
                            ]
                        )
                    }
                )

                // Then
                await #expect(
                    runMetadataStorage.selectiveTestingCacheItems == [
                        temporaryPath: [
                            "AUnitTests": CacheItem(
                                name: "AUnitTests",
                                hash: "hash-a-unit-tests",
                                source: .miss,
                                cacheCategory: .selectiveTests
                            ),
                        ],
                    ]
                )
            }
        }
    }

    @Test func skipsCachedTestsOfDefaultTestPlan() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            // Given
            let aUnitTestsTarget: Target = .test(name: "AUnitTests")
            let bUnitTestsTarget: Target = .test(name: "BUnitTests")
            let project: Project = .test(
                targets: [
                    aUnitTestsTarget,
                    bUnitTestsTarget,
                ],
                schemes: [
                    .test(
                        name: "App",
                        testAction: .test(
                            targets: [
                                TestableTarget(
                                    target: TargetReference(
                                        projectPath: temporaryPath,
                                        name: "AUnitTests"
                                    )
                                ),
                            ],
                            testPlans: [
                                TestPlan(
                                    path: temporaryPath.appending(
                                        component: "MyTestPlan.xctestplan"
                                    ),
                                    testTargets: [
                                        TestableTarget(
                                            target: TargetReference(
                                                projectPath: temporaryPath,
                                                name: "AUnitTests"
                                            )
                                        ),
                                        TestableTarget(
                                            target: TargetReference(
                                                projectPath: temporaryPath,
                                                name: "BUnitTests"
                                            )
                                        ),
                                    ],
                                    isDefault: true
                                ),
                            ]
                        )
                    ),
                ]
            )

            given(xcodeGraphMapper)
                .map(at: .any)
                .willReturn(
                    .test(
                        projects: [
                            temporaryPath: project,
                        ]
                    )
                )

            given(selectiveTestingGraphHasher)
                .hash(
                    graph: .any,
                    additionalStrings: .any
                )
                .willReturn(
                    [
                        GraphTarget(
                            path: project.path,
                            target: aUnitTestsTarget,
                            project: project
                        ): .test(hash: "hash-a-unit-tests"),
                        GraphTarget(
                            path: project.path,
                            target: bUnitTestsTarget,
                            project: project
                        ): .test(hash: "hash-b-unit-tests"),
                    ]
                )
            given(selectiveTestingService)
                .cachedTests(
                    testableGraphTargets: .any,
                    selectiveTestingHashes: .any,
                    selectiveTestingCacheItems: .any
                )
                .willReturn(
                    [
                        try TestIdentifier(string: "AUnitTests"),
                        try TestIdentifier(string: "BUnitTests"),
                    ]
                )

            given(cacheStorage)
                .fetch(.any, cacheCategory: .any)
                .willReturn(
                    [
                        CacheItem(
                            name: "AUnitTests",
                            hash: "hash-a-unit-tests",
                            source: .local,
                            cacheCategory: .selectiveTests
                        ): temporaryPath,
                        CacheItem(
                            name: "BUnitTests",
                            hash: "hash-b-unit-tests",
                            source: .local,
                            cacheCategory: .selectiveTests
                        ): temporaryPath,
                    ]
                )

            // When
            try await subject.run(
                passthroughXcodebuildArguments: [
                    "test",
                    "-scheme", "App",
                    "-testPlan", "MyTestPlan",
                ]
            )

            // Then
            verify(xcodeBuildController)
                .run(
                    arguments: .any
                )
                .called(0)
        }
    }

    @Test func skipsCachedTestsOfCustomTestPlan() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            // Given
            let aUnitTestsTarget: Target = .test(name: "AUnitTests")
            let bUnitTestsTarget: Target = .test(name: "BUnitTests")
            let project: Project = .test(
                targets: [
                    aUnitTestsTarget,
                    bUnitTestsTarget,
                ],
                schemes: [
                    .test(
                        name: "App",
                        testAction: .test(
                            testPlans: [
                                TestPlan(
                                    path: temporaryPath.appending(
                                        component: "MyTestPlan.xctestplan"
                                    ),
                                    testTargets: [
                                        TestableTarget(
                                            target: TargetReference(
                                                projectPath: temporaryPath,
                                                name: "AUnitTests"
                                            )
                                        ),
                                        TestableTarget(
                                            target: TargetReference(
                                                projectPath: temporaryPath,
                                                name: "BUnitTests"
                                            )
                                        ),
                                    ],
                                    isDefault: false
                                ),
                            ]
                        )
                    ),
                ]
            )

            given(xcodeGraphMapper)
                .map(at: .any)
                .willReturn(
                    .test(
                        projects: [
                            temporaryPath: project,
                        ]
                    )
                )

            given(selectiveTestingGraphHasher)
                .hash(
                    graph: .any,
                    additionalStrings: .any
                )
                .willReturn(
                    [
                        GraphTarget(
                            path: project.path,
                            target: aUnitTestsTarget,
                            project: project
                        ): .test(hash: "hash-a-unit-tests"),
                        GraphTarget(
                            path: project.path,
                            target: bUnitTestsTarget,
                            project: project
                        ): .test(hash: "hash-b-unit-tests"),
                    ]
                )
            given(selectiveTestingService)
                .cachedTests(
                    testableGraphTargets: .any,
                    selectiveTestingHashes: .any,
                    selectiveTestingCacheItems: .any
                )
                .willReturn(
                    [
                        try TestIdentifier(string: "AUnitTests"),
                    ]
                )

            given(cacheStorage)
                .fetch(.any, cacheCategory: .any)
                .willReturn(
                    [
                        CacheItem(
                            name: "AUnitTests",
                            hash: "hash-a-unit-tests",
                            source: .local,
                            cacheCategory: .selectiveTests
                        ): temporaryPath,
                    ]
                )

            // When
            try await subject.run(
                passthroughXcodebuildArguments: [
                    "test",
                    "-scheme", "App",
                    "-testPlan", "MyTestPlan",
                ]
            )

            // Then
            verify(xcodeBuildController)
                .run(
                    arguments: .value(
                        [
                            "test",
                            "-scheme", "App",
                            "-testPlan", "MyTestPlan",
                            "-skip-testing:AUnitTests",
                            "-resultBundlePath", "/tmp/runs/unique-id",
                        ]
                    )
                )
                .called(1)
        }
    }

    @Test func preservesResultBundlePathWhenPassed() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            let runMetadataStorage = RunMetadataStorage()
            try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                // Given
                let aUnitTestsTarget: Target = .test(name: "AUnitTests")
                let bUnitTestsTarget: Target = .test(name: "BUnitTests")
                let project: Project = .test(
                    path: temporaryPath,
                    targets: [
                        aUnitTestsTarget,
                        bUnitTestsTarget,
                    ],
                    schemes: [
                        .test(
                            name: "App",
                            testAction: .test(
                                targets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: temporaryPath,
                                            name: "AUnitTests"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )

                given(xcodeGraphMapper)
                    .map(at: .any)
                    .willReturn(
                        .test(
                            projects: [
                                temporaryPath: project,
                            ]
                        )
                    )

                given(selectiveTestingGraphHasher)
                    .hash(
                        graph: .any,
                        additionalStrings: .any
                    )
                    .willReturn([:])
                given(selectiveTestingService)
                    .cachedTests(
                        testableGraphTargets: .any,
                        selectiveTestingHashes: .any,
                        selectiveTestingCacheItems: .any
                    )
                    .willReturn([])

                given(cacheStorage)
                    .fetch(.any, cacheCategory: .any)
                    .willReturn([:])

                // When
                try await subject.run(
                    passthroughXcodebuildArguments: [
                        "test",
                        "-scheme", "App",
                        "-resultBundlePath", "/custom-path",
                    ]
                )

                // Then
                verify(xcodeBuildController)
                    .run(
                        arguments: .value(
                            [
                                "test",
                                "-scheme", "App",
                                "-resultBundlePath", "/custom-path",
                            ]
                        )
                    )
                    .called(1)
                let resultBundlePath = try AbsolutePath(validating: "/custom-path")
                await #expect(runMetadataStorage.resultBundlePath == resultBundlePath)
            }
        }
    }

    @Test func logsWarningWhenInspectResultBundleFails() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "XcodeBuildTestCommandServiceTests") {
            temporaryPath in
            let runMetadataStorage = RunMetadataStorage()
            let alertController = AlertController()
            try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                try await AlertController.$current.withValue(alertController) {
                    // Given
                    let aUnitTestsTarget: Target = .test(name: "AUnitTests")
                    let project: Project = .test(
                        path: temporaryPath,
                        targets: [
                            aUnitTestsTarget,
                        ],
                        schemes: [
                            .test(
                                name: "App",
                                testAction: .test(
                                    targets: [
                                        .test(
                                            target: TargetReference(
                                                projectPath: temporaryPath,
                                                name: "AUnitTests"
                                            )
                                        ),
                                    ]
                                )
                            ),
                        ]
                    )

                    given(xcodeGraphMapper)
                        .map(at: .any)
                        .willReturn(
                            .test(
                                projects: [
                                    temporaryPath: project,
                                ]
                            )
                        )

                    given(selectiveTestingGraphHasher)
                        .hash(
                            graph: .any,
                            additionalStrings: .any
                        )
                        .willReturn([:])
                    given(selectiveTestingService)
                        .cachedTests(
                            testableGraphTargets: .any,
                            selectiveTestingHashes: .any,
                            selectiveTestingCacheItems: .any
                        )
                        .willReturn([])

                    given(cacheStorage)
                        .fetch(.any, cacheCategory: .any)
                        .willReturn([:])

                    configLoader.reset()
                    given(configLoader)
                        .loadConfig(path: .any)
                        .willReturn(.test(fullHandle: "tuist/tuist"))

                    let resultBundlePath = temporaryPath.appending(component: "test.xcresult")
                    try await fileSystem.makeDirectory(at: resultBundlePath)

                    given(inspectResultBundleService)
                        .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
                        .willThrow(TestError("Inspect failed"))

                    // When
                    try await subject.run(
                        passthroughXcodebuildArguments: [
                            "test",
                            "-scheme", "App",
                            "-resultBundlePath", resultBundlePath.pathString,
                        ]
                    )

                    // Then
                    verify(inspectResultBundleService)
                        .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
                        .called(1)
                    let warnings = alertController.warnings()
                    #expect(warnings.count == 1)
                    #expect(warnings.first?.message.plain().contains("Failed to upload test results") == true)
                }
            }
        }
    }
}

@Mockable
protocol XcodeGraphMapping: XcodeGraphMapper.XcodeGraphMapping {
    func map(at path: AbsolutePath) async throws -> Graph
}
