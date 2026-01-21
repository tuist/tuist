import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct QueryDepsServiceTests {
    private let manifestGraphLoader = MockManifestGraphLoading()
    private let manifestLoader = MockManifestLoading()
    private let xcodeGraphMapper = MockXcodeGraphMapping()
    private let configLoader = MockConfigLoading()
    private let subject: QueryDepsService

    init() {
        subject = QueryDepsService(
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            xcodeGraphMapper: xcodeGraphMapper,
            configLoader: configLoader
        )
    }

    @Test(.inTemporaryDirectory) func run_withListFormat_outputsTargetsAndDependencies() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                format: .list
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withTreeFormat_outputsTargetsAsTree() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                format: .tree
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withJSONFormat_outputsValidJSON() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                format: .json
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withNoRootManifest_usesXcodeGraphMapper() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(false)

            given(xcodeGraphMapper)
                .map(at: .any)
                .willReturn(.test())

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                format: .list
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withSourceFilter_filtersToSourceDependencies() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: ["App"],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                format: .list
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withSinkFilter_filtersToSinkDependencies() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: ["Core"],
                directOnly: false,
                typeFilter: [],
                format: .list
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withDirectOnly_showsOnlyDirectDependencies() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: ["App"],
                sinkTargets: [],
                directOnly: true,
                typeFilter: [],
                format: .list
            )
        }
    }

    @Test(.inTemporaryDirectory) func run_withTypeFilter_filtersToSpecificTypes() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                path: temporaryDirectory,
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: ["target", "framework"],
                format: .list
            )
        }
    }
}
