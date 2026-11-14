import FileSystem
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistInspectCommand
@testable import TuistKit

struct TargetImportsScannerTests {
    private let fileSystem = FileSystem()

    @Test func imports() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

            let targetFirstFile = targetPath.appending(component: "FirstFile.swift")
            let targetSecondFile = targetPath.appending(component: "SecondFile.swift")

            try await fileSystem.makeDirectory(at: targetPath)

            try await fileSystem.writeText(
                """
                import SecondTarget
                import A

                let a = 5
                """,
                at: targetFirstFile
            )

            try await fileSystem.writeText(
                """
                @testable import ThirdTarget

                func main() { }
                """,
                at: targetSecondFile
            )

            let target = Target.test(
                name: "FirstTarget",
                sources: [
                    SourceFile(path: targetFirstFile),
                    SourceFile(path: targetSecondFile),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_in_buildable_folder_sources() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

            let targetFirstFile = targetPath.appending(component: "FirstFile.swift")
            let targetSecondFile = targetPath.appending(component: "SecondFile.swift")

            try await fileSystem.makeDirectory(at: targetPath)

            try await fileSystem.writeText(
                """
                import SecondTarget
                import A

                let a = 5
                """,
                at: targetFirstFile
            )

            try await fileSystem.writeText(
                """
                @testable import ThirdTarget

                func main() { }
                """,
                at: targetSecondFile
            )

            let target = Target.test(
                name: "FirstTarget",
                buildableFolders: [
                    BuildableFolder(
                        path: "/Sources",
                        exceptions: [],
                        resolvedFiles: [
                            BuildableFolderFile(path: targetFirstFile, compilerFlags: nil),
                            BuildableFolderFile(path: targetSecondFile, compilerFlags: nil),
                        ]
                    ),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_when_filesAreAbsent() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let sourcesPath = temporaryDirectory.appending(components: "Target", "Sources")
            let sourcePath = sourcesPath.appending(component: "Source.swift")
            let target = Target.test(
                name: "Target",
                sources: [
                    SourceFile(path: sourcePath),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == [])
        }
    }

    @Test func imports_limitsConcurrentFileScans() async throws {
        // Given
        let sourceCodeReader = ConcurrentSourceCodeReader()
        let sources = try (0 ..< 20).map { index -> SourceFile in
            let path = try AbsolutePath(validating: "/Target/Sources/File\(index).swift")
            return SourceFile(path: path)
        }
        let target = Target.test(
            name: "FirstTarget",
            sources: sources
        )

        // When
        let result = try await TargetImportsScanner(
            maxConcurrentFileScans: 3,
            sourceCodeReader: sourceCodeReader.read(at:)
        )
        .imports(for: target)

        // Then
        #expect(result == ["SecondTarget"])
        #expect(await sourceCodeReader.maxConcurrentReads <= 3)
    }

    @Test func imports_limitsConcurrentFileScansAcrossTargetsAndScansSharedFilesOnce() async throws {
        // Given
        let sourceCodeReader = ConcurrentSourceCodeReader()
        let sharedSource = SourceFile(path: try AbsolutePath(validating: "/Shared/Sources/Shared.swift"))
        let targets = try (0 ..< 4).map { targetIndex in
            let sources = try (0 ..< 5).map { index in
                SourceFile(path: try AbsolutePath(validating: "/Target\(targetIndex)/Sources/File\(index).swift"))
            }
            return Target.test(name: "Target\(targetIndex)", sources: sources + [sharedSource])
        }
        let subject = TargetImportsScanner(
            maxConcurrentFileScans: 3,
            sourceCodeReader: sourceCodeReader.read(at:)
        )

        // When
        let results = try await targets.concurrentMap(maxConcurrentTasks: targets.count) { target in
            try await subject.imports(for: target)
        }

        // Then
        #expect(results == Array(repeating: ["SecondTarget"], count: targets.count))
        #expect(await sourceCodeReader.maxConcurrentReads <= 3)
        #expect(await sourceCodeReader.reads == 21)
    }

    @Test func imports_readsEachFileOnceAcrossDifferentReachableModules() async throws {
        // Given
        let sourceCodeReader = CountingSourceCodeReader(
            sourceCode: """
            import A
            #if canImport(B)
            import B
            #endif
            """
        )
        let target = Target.test(
            name: "FirstTarget",
            sources: [SourceFile(path: try AbsolutePath(validating: "/Target/Sources/File.swift"))]
        )
        let subject = TargetImportsScanner(sourceCodeReader: sourceCodeReader.read(at:))

        // When
        let withoutB = try await subject.imports(for: target, reachableModules: [])
        let withB = try await subject.imports(for: target, reachableModules: ["B"])

        // Then
        #expect(withoutB == ["A"])
        #expect(withB == ["A", "B"])
        #expect(await sourceCodeReader.reads == 1)
    }

    @Test func imports_cachesMissingFilesAndSkipsNonSourceFiles() async throws {
        // Given
        let sourceCodeReader = CountingSourceCodeReader(sourceCode: nil)
        let target = Target.test(
            name: "FirstTarget",
            sources: [
                SourceFile(path: try AbsolutePath(validating: "/Target/Sources/Missing.swift")),
                SourceFile(path: try AbsolutePath(validating: "/Target/Resources/data.json")),
            ]
        )
        let subject = TargetImportsScanner(sourceCodeReader: sourceCodeReader.read(at:))

        // When
        let first = try await subject.imports(for: target, reachableModules: [])
        let second = try await subject.imports(for: target, reachableModules: ["A"])

        // Then
        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(await sourceCodeReader.reads == 1)
    }
}

private actor CountingSourceCodeReader {
    private let sourceCode: String?
    private(set) var reads = 0

    init(sourceCode: String?) {
        self.sourceCode = sourceCode
    }

    func read(at _: AbsolutePath) async throws -> String? {
        reads += 1
        return sourceCode
    }
}

private actor ConcurrentSourceCodeReader {
    private var activeReads = 0
    private(set) var maxConcurrentReads = 0
    private(set) var reads = 0

    func read(at _: AbsolutePath) async throws -> String? {
        reads += 1
        activeReads += 1
        maxConcurrentReads = max(maxConcurrentReads, activeReads)
        defer { activeReads -= 1 }

        try await Task.sleep(nanoseconds: 10_000_000)
        return "import SecondTarget"
    }
}
