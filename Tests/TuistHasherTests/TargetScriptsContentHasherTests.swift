import FileSystem
import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class TargetScriptsContentHasherTests: TuistUnitTestCase {
    private var subject: TargetScriptsContentHasher!

    override func setUp() async throws {
        try await super.setUp()
        subject = TargetScriptsContentHasher(contentHasher: ContentHasher())
    }

    override func tearDown() async throws {
        subject = nil
        try await super.tearDown()
    }

    func test_hash_isDeterministic() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let dependencyFile = temporaryDirectory.appending(component: "dependency.d")
        try await fileSystem.touch(dependencyFile)
        let targetScripts: [TargetScript] = [
            TargetScript(
                name: "script",
                order: .pre,
                script: .embedded("echo 'foo'"),
                inputPaths: [],
                inputFileListPaths: [],
                outputPaths: [],
                outputFileListPaths: [],
                showEnvVarsInLog: true,
                basedOnDependencyAnalysis: true,
                runForInstallBuildsOnly: true,
                shellPath: "/bin/env bash",
                dependencyFile: dependencyFile
            ),
        ]
        var hashes: Set<String> = Set()

        // When
        for _ in 0 ... 100 {
            hashes.insert(try subject.hash(
                identifier: "targetScripts",
                targetScripts: targetScripts,
                sourceRootPath: temporaryDirectory
            ).hash)
        }

        // Then
        XCTAssertEqual(hashes.count, 1)
    }

    func test_hash_returnsACorrectValue_when_embedded() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let inputFilePath = temporaryDirectory.appending(component: "input")
        let inputFileListPath = temporaryDirectory.appending(component: "input.xcfilelist")
        let dependencyFilePath = temporaryDirectory.appending(component: "dependency.d")
        let outputFileListPath = temporaryDirectory.appending(component: "output.xcfilelist")

        try await fileSystem.touch(inputFilePath)
        try await fileSystem.touch(inputFileListPath)
        try await fileSystem.touch(dependencyFilePath)
        try await fileSystem.touch(outputFileListPath)

        let targetScripts: [TargetScript] = [
            TargetScript(
                name: "script",
                order: .pre,
                script: .embedded("echo 'foo'"),
                inputPaths: [inputFilePath.pathString],
                inputFileListPaths: [inputFileListPath],
                outputPaths: ["$(DERIVED_FILE_DIR)/output"],
                outputFileListPaths: [outputFileListPath],
                showEnvVarsInLog: true,
                basedOnDependencyAnalysis: true,
                runForInstallBuildsOnly: true,
                shellPath: "/bin/env bash",
                dependencyFile: dependencyFilePath
            ),
        ]

        // When
        let got = try subject.hash(identifier: "targetScripts", targetScripts: targetScripts, sourceRootPath: temporaryDirectory)

        // Then

        XCTAssertBetterEqual(got, MerkleNode(
            hash: "f998595a4c29c055986eea0f161c2414",
            identifier: "targetScripts",
            children: [
                MerkleNode(
                    hash: "4f46d0a08b22aa87400cf7d42f11b2eb",
                    identifier: "script",
                    children: [
                        MerkleNode(
                            hash: "3205c0ded576131ea255ad2bd38b0fb2",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "6bf9e70a1f928aba143ef1eebe2720b5",
                            identifier: "order",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "arguments",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "showEnvVarsInLog",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "runForInstallBuildsOnly",
                            children: []
                        ),
                        MerkleNode(
                            hash: "7c8004fdd34501290a365abf0a8075af",
                            identifier: "shellPath",
                            children: []
                        ),
                        MerkleNode(
                            hash: "e7fb3c7d0d873bd34060e7dd99ab2f0c",
                            identifier: "embeddedScript",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "basedOnDependencyAnalysis",
                            children: []
                        ),
                        MerkleNode(
                            hash: "e7fb3c7d0d873bd34060e7dd99ab2f0c",
                            identifier: "embeddedScript",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "dependency.d",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputFileListPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "outputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "ea2b5501efdb4691fb32d16a029e5dea",
                            identifier: "outputFileListPaths",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }

    func test_hash_returnsACorrectValue_when_tool() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let inputFilePath = temporaryDirectory.appending(component: "input")
        let inputFileListPath = temporaryDirectory.appending(component: "input.xcfilelist")
        let dependencyFilePath = temporaryDirectory.appending(component: "dependency.d")
        let outputFileListPath = temporaryDirectory.appending(component: "output.xcfilelist")

        try await fileSystem.touch(inputFilePath)
        try await fileSystem.touch(inputFileListPath)
        try await fileSystem.touch(dependencyFilePath)
        try await fileSystem.touch(outputFileListPath)

        let targetScripts: [TargetScript] = [
            TargetScript(
                name: "script",
                order: .pre,
                script: .tool(path: "tool", args: ["foo", "bar"]),
                inputPaths: [inputFilePath.pathString],
                inputFileListPaths: [inputFileListPath],
                outputPaths: ["$(DERIVED_FILE_DIR)/output"],
                outputFileListPaths: [outputFileListPath],
                showEnvVarsInLog: true,
                basedOnDependencyAnalysis: true,
                runForInstallBuildsOnly: true,
                shellPath: "/bin/env bash",
                dependencyFile: dependencyFilePath
            ),
        ]

        // When
        let got = try subject.hash(identifier: "targetScripts", targetScripts: targetScripts, sourceRootPath: temporaryDirectory)

        // Then
        XCTAssertBetterEqual(got, MerkleNode(
            hash: "6195645d6ce4841d46aaef61e288b0fc",
            identifier: "targetScripts",
            children: [
                MerkleNode(
                    hash: "98a2441ccd73e19dd9147555b9f20b44",
                    identifier: "script",
                    children: [
                        MerkleNode(
                            hash: "3205c0ded576131ea255ad2bd38b0fb2",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "6bf9e70a1f928aba143ef1eebe2720b5",
                            identifier: "order",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3858f62230ac3c915f300c664312c63f",
                            identifier: "arguments",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "showEnvVarsInLog",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "runForInstallBuildsOnly",
                            children: []
                        ),
                        MerkleNode(
                            hash: "7c8004fdd34501290a365abf0a8075af",
                            identifier: "shellPath",
                            children: []
                        ),
                        MerkleNode(
                            hash: "39ab32c5aeb56c9f5ae17f073ce31023",
                            identifier: "tool",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3858f62230ac3c915f300c664312c63f",
                            identifier: "arguments",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "basedOnDependencyAnalysis",
                            children: []
                        ),
                        MerkleNode(
                            hash: "39ab32c5aeb56c9f5ae17f073ce31023",
                            identifier: "tool",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "dependency.d",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputFileListPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "outputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "ea2b5501efdb4691fb32d16a029e5dea",
                            identifier: "outputFileListPaths",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }

    func test_hash_returnsACorrectValue_when_script() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try temporaryPath()
        let scriptPath = temporaryDirectory.appending(component: "script")
        let inputFilePath = temporaryDirectory.appending(component: "input")
        let inputFileListPath = temporaryDirectory.appending(component: "input.xcfilelist")
        let dependencyFilePath = temporaryDirectory.appending(component: "dependency.d")
        let outputFileListPath = temporaryDirectory.appending(component: "output.xcfilelist")

        try await fileSystem.writeText("script", at: scriptPath)
        try await fileSystem.touch(inputFilePath)
        try await fileSystem.touch(inputFileListPath)
        try await fileSystem.touch(dependencyFilePath)
        try await fileSystem.touch(outputFileListPath)

        let targetScripts: [TargetScript] = [
            TargetScript(
                name: "script",
                order: .pre,
                script: .scriptPath(path: scriptPath, args: ["foo", "bar"]),
                inputPaths: [inputFilePath.pathString],
                inputFileListPaths: [inputFileListPath],
                outputPaths: ["$(DERIVED_FILE_DIR)/output"],
                outputFileListPaths: [outputFileListPath],
                showEnvVarsInLog: true,
                basedOnDependencyAnalysis: true,
                runForInstallBuildsOnly: true,
                shellPath: "/bin/env bash",
                dependencyFile: dependencyFilePath
            ),
        ]

        // When
        let got = try subject.hash(identifier: "targetScripts", targetScripts: targetScripts, sourceRootPath: temporaryDirectory)

        // Then
        XCTAssertBetterEqual(got, MerkleNode(
            hash: "46223dd29e214ec27955fc296754bb6c",
            identifier: "targetScripts",
            children: [
                MerkleNode(
                    hash: "e42251f58a728466cf96d5e032550493",
                    identifier: "script",
                    children: [
                        MerkleNode(
                            hash: "3205c0ded576131ea255ad2bd38b0fb2",
                            identifier: "name",
                            children: []
                        ),
                        MerkleNode(
                            hash: "6bf9e70a1f928aba143ef1eebe2720b5",
                            identifier: "order",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3858f62230ac3c915f300c664312c63f",
                            identifier: "arguments",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "showEnvVarsInLog",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "runForInstallBuildsOnly",
                            children: []
                        ),
                        MerkleNode(
                            hash: "7c8004fdd34501290a365abf0a8075af",
                            identifier: "shellPath",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3205c0ded576131ea255ad2bd38b0fb2",
                            identifier: "script",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3858f62230ac3c915f300c664312c63f",
                            identifier: "arguments",
                            children: []
                        ),
                        MerkleNode(
                            hash: "c4ca4238a0b923820dcc509a6f75849b",
                            identifier: "basedOnDependencyAnalysis",
                            children: []
                        ),
                        MerkleNode(
                            hash: "3205c0ded576131ea255ad2bd38b0fb2",
                            identifier: "script",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "dependency.d",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "74be16979710d4c4e7c6647856088456",
                            identifier: "inputFileListPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "d41d8cd98f00b204e9800998ecf8427e",
                            identifier: "outputPaths",
                            children: []
                        ),
                        MerkleNode(
                            hash: "ea2b5501efdb4691fb32d16a029e5dea",
                            identifier: "outputFileListPaths",
                            children: []
                        ),
                    ]
                ),
            ]
        ))
    }
}
