import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAppleArchiver

struct AppleArchiverTests {
    let subject = AppleArchiver()

    @Test(.inTemporaryDirectory) func compress_and_decompress_roundtrip() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("hello world", at: sourceDir.appending(component: "file.txt"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let exists = try await fileSystem.exists(archivePath)
        #expect(exists)

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let content = try await fileSystem.readTextFile(at: extractDir.appending(component: "file.txt"))
        #expect(content == "hello world")
    }

    @Test(.inTemporaryDirectory) func compress_and_decompress_preserves_symlinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("target content", at: sourceDir.appending(component: "target.txt"))
        try await fileSystem.createSymbolicLink(
            from: sourceDir.appending(component: "link"),
            to: try RelativePath(validating: "target.txt")
        )

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let resolvedLink = try await fileSystem.resolveSymbolicLink(extractDir.appending(component: "link"))
        #expect(resolvedLink == extractDir.appending(component: "target.txt"))

        let content = try await fileSystem.readTextFile(at: extractDir.appending(component: "link"))
        #expect(content == "target content")
    }

    @Test(.inTemporaryDirectory) func compress_and_decompress_preserves_directory_structure() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        let nestedDir = sourceDir.appending(components: ["a", "b", "c"])
        try await fileSystem.makeDirectory(at: nestedDir)
        try await fileSystem.writeText("deep", at: nestedDir.appending(component: "deep.txt"))
        try await fileSystem.writeText("root", at: sourceDir.appending(component: "root.txt"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let rootContent = try await fileSystem.readTextFile(at: extractDir.appending(component: "root.txt"))
        #expect(rootContent == "root")

        let deepContent = try await fileSystem.readTextFile(
            at: extractDir.appending(components: ["a", "b", "c", "deep.txt"])
        )
        #expect(deepContent == "deep")
    }

    @Test(.inTemporaryDirectory) func compress_excludes_matching_patterns() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("keep", at: sourceDir.appending(component: "file.txt"))
        let dsymDir = sourceDir.appending(components: ["Module.framework.dSYM", "Contents", "Resources"])
        try await fileSystem.makeDirectory(at: dsymDir)
        try await fileSystem.writeText("debug", at: dsymDir.appending(component: "DWARF"))
        let swiftmoduleDir = sourceDir.appending(component: "Module.swiftmodule")
        try await fileSystem.makeDirectory(at: swiftmoduleDir)
        try await fileSystem.writeText("module", at: swiftmoduleDir.appending(component: "arm64.swiftmodule"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(
            directory: sourceDir,
            to: archivePath,
            excludePatterns: [".dSYM", ".swiftmodule"]
        )

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let fileExists = try await fileSystem.exists(extractDir.appending(component: "file.txt"))
        #expect(fileExists)
        let dsymExists = try await fileSystem.exists(extractDir.appending(component: "Module.framework.dSYM"))
        #expect(!dsymExists)
        let swiftmoduleExists = try await fileSystem.exists(extractDir.appending(component: "Module.swiftmodule"))
        #expect(!swiftmoduleExists)
    }

    /// Guards the shard split: excludePatterns is a substring match, so ".xctest" would also drop the
    /// sibling ".xctestrun" (which contains it). ".xctest/" must exclude only the bundle's contents.
    @Test(.inTemporaryDirectory) func compress_excludeXCTestBundle_keepsXCTestRun() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        let xctestMacOS = sourceDir.appending(components: ["AppTests.xctest", "Contents", "MacOS"])
        try await fileSystem.makeDirectory(at: xctestMacOS)
        try await fileSystem.writeText("binary", at: xctestMacOS.appending(component: "AppTests"))
        try await fileSystem.writeText("run", at: sourceDir.appending(component: "AppTests.xctestrun"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [".xctest/"])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let xctestRunExists = try await fileSystem.exists(extractDir.appending(component: "AppTests.xctestrun"))
        #expect(xctestRunExists)
        let xctestBinaryExists = try await fileSystem.exists(
            extractDir.appending(components: ["AppTests.xctest", "Contents", "MacOS", "AppTests"])
        )
        #expect(!xctestBinaryExists)
        let xctestDirectoryExists = try await fileSystem.exists(extractDir.appending(component: "AppTests.xctest"))
        #expect(!xctestDirectoryExists)
    }

    @Test(.inTemporaryDirectory) func splitShardArchives_extractTogetherIntoProductsBundle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let productsDir = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: productsDir)
        try await fileSystem.writeText("run", at: productsDir.appending(component: "MyApp.xctestrun"))

        let buildDir = productsDir.appending(components: "Binaries", "Debug")
        let appTests = buildDir.appending(component: "AppTests.xctest")
        try await fileSystem.makeDirectory(at: appTests)
        try await fileSystem.writeText("app-tests", at: appTests.appending(component: "AppTests"))
        let coreTests = buildDir.appending(component: "CoreTests.xctest")
        try await fileSystem.makeDirectory(at: coreTests)
        try await fileSystem.writeText("core-tests", at: coreTests.appending(component: "CoreTests"))
        let sharedFramework = buildDir.appending(component: "Shared.framework")
        try await fileSystem.makeDirectory(at: sharedFramework)
        try await fileSystem.writeText("shared", at: sharedFramework.appending(component: "Shared"))

        let sharedArchive = temporaryDirectory.appending(component: "shared.aar")
        try await subject.compress(directory: productsDir, to: sharedArchive, excludePatterns: [".dSYM", ".xctest/"])
        let appTestsArchive = temporaryDirectory.appending(component: "AppTests.aar")
        try await subject.compress(subdirectory: appTests, relativeTo: productsDir, to: appTestsArchive)
        let coreTestsArchive = temporaryDirectory.appending(component: "CoreTests.aar")
        try await subject.compress(subdirectory: coreTests, relativeTo: productsDir, to: coreTestsArchive)

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: sharedArchive, to: extractDir)
        try await subject.decompress(archive: appTestsArchive, to: extractDir)
        try await subject.decompress(archive: coreTestsArchive, to: extractDir)

        let xctestRunExists = try await fileSystem.exists(extractDir.appending(component: "MyApp.xctestrun"))
        #expect(xctestRunExists)
        let sharedFrameworkExists = try await fileSystem.exists(
            extractDir.appending(components: "Binaries", "Debug", "Shared.framework", "Shared")
        )
        #expect(sharedFrameworkExists)
        let appTestsBinary = try await fileSystem.readTextFile(
            at: extractDir.appending(components: "Binaries", "Debug", "AppTests.xctest", "AppTests")
        )
        #expect(appTestsBinary == "app-tests")
        let coreTestsBinary = try await fileSystem.readTextFile(
            at: extractDir.appending(components: "Binaries", "Debug", "CoreTests.xctest", "CoreTests")
        )
        #expect(coreTestsBinary == "core-tests")
    }

    @Test(.inTemporaryDirectory) func compress_preservesBaseDirectory_wrapsContentsInBundleName() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let bundleDir = temporaryDirectory.appending(component: "result.xcresult")
        try await fileSystem.makeDirectory(at: bundleDir)
        try await fileSystem.writeText("plist", at: bundleDir.appending(component: "Info.plist"))
        try await fileSystem.writeText("db", at: bundleDir.appending(component: "database.sqlite3"))

        // A sibling that shares no prefix with the bundle should be pruned.
        let sibling = temporaryDirectory.appending(component: "unrelated")
        try await fileSystem.makeDirectory(at: sibling)
        try await fileSystem.writeText("nope", at: sibling.appending(component: "leak.txt"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(
            directory: bundleDir,
            to: archivePath,
            excludePatterns: [],
            preservesBaseDirectory: true
        )

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        // Bundle is wrapped in its basename so extractors land at
        // `extractDir/result.xcresult/…` — what Xcode and the server-side
        // xcresult processor expect.
        let extractedBundle = extractDir.appending(component: "result.xcresult")
        let plistExists = try await fileSystem.exists(extractedBundle.appending(component: "Info.plist"))
        #expect(plistExists)
        let dbExists = try await fileSystem.exists(extractedBundle.appending(component: "database.sqlite3"))
        #expect(dbExists)

        let leakedSibling = try await fileSystem.exists(extractDir.appending(component: "unrelated"))
        #expect(!leakedSibling)
    }

    @Test(.inTemporaryDirectory)
    func compress_preservesBaseDirectory_excludePatternsMatchPathsWithinBundle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        // The bundle's own basename contains ".dSYM" — exclude patterns must
        // match against entries *inside* the bundle, not the wrapper itself,
        // otherwise the whole bundle would be skipped.
        let bundleDir = temporaryDirectory.appending(component: "Module.framework.dSYM")
        try await fileSystem.makeDirectory(at: bundleDir)
        try await fileSystem.writeText("keep", at: bundleDir.appending(component: "Info.plist"))
        let nestedDsym = bundleDir.appending(components: ["Resources", "DWARF.dSYM"])
        try await fileSystem.makeDirectory(at: nestedDsym)
        try await fileSystem.writeText("strip", at: nestedDsym.appending(component: "binary"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(
            directory: bundleDir,
            to: archivePath,
            excludePatterns: [".dSYM"],
            preservesBaseDirectory: true
        )

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let extractedBundle = extractDir.appending(component: "Module.framework.dSYM")
        let plistExists = try await fileSystem.exists(extractedBundle.appending(component: "Info.plist"))
        #expect(plistExists)
        let nestedExists = try await fileSystem.exists(extractedBundle.appending(component: "Resources"))
        #expect(!nestedExists)
    }

    @Test(.inTemporaryDirectory) func compress_handles_broken_symlinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("keep", at: sourceDir.appending(component: "file.txt"))
        try await fileSystem.createSymbolicLink(
            from: sourceDir.appending(component: "broken_link"),
            to: try AbsolutePath(validating: "/nonexistent/target")
        )

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let fileContent = try await fileSystem.readTextFile(at: extractDir.appending(component: "file.txt"))
        #expect(fileContent == "keep")
        let linkDest = try FileManager.default.destinationOfSymbolicLink(
            atPath: extractDir.appending(component: "broken_link").pathString
        )
        #expect(linkDest == "/nonexistent/target")
    }

    /// The shard split archives one module's `.xctest` out of a products directory that also holds
    /// the other modules and the shared bundle. The archive must carry the `.xctest`'s full path
    /// relative to the products root (so it merges back in place), while nothing else is read.
    @Test(.inTemporaryDirectory) func compress_subdirectory_preservesRelativePath_andPrunesSiblings() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let productsDir = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        let builtProductsDir = productsDir.appending(components: ["Binaries", "0", "Debug-iphonesimulator"])
        let targetXCTest = builtProductsDir.appending(component: "FooTests.xctest")
        try await fileSystem.makeDirectory(at: targetXCTest)
        try await fileSystem.writeText("foo-binary", at: targetXCTest.appending(component: "FooTests"))

        // A sibling module and a shared framework in the same built-products directory, plus a
        // root-level file — none of these should be read into the module archive.
        let siblingXCTest = builtProductsDir.appending(component: "BarTests.xctest")
        try await fileSystem.makeDirectory(at: siblingXCTest)
        try await fileSystem.writeText("bar-binary", at: siblingXCTest.appending(component: "BarTests"))
        let framework = builtProductsDir.appending(component: "Shared.framework")
        try await fileSystem.makeDirectory(at: framework)
        try await fileSystem.writeText("shared", at: framework.appending(component: "Shared"))
        try await fileSystem.writeText("meta", at: productsDir.appending(component: "run-metadata.json"))

        let archivePath = temporaryDirectory.appending(component: "FooTests.aar")
        try await subject.compress(subdirectory: targetXCTest, relativeTo: productsDir, to: archivePath)

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        // The target lands at its original relative path.
        let extractedBinary = extractDir.appending(
            components: ["Binaries", "0", "Debug-iphonesimulator", "FooTests.xctest", "FooTests"]
        )
        let extractedContent = try await fileSystem.readTextFile(at: extractedBinary)
        #expect(extractedContent == "foo-binary")

        // Everything outside the target subtree is pruned.
        let siblingExists = try await fileSystem.exists(
            extractDir.appending(components: ["Binaries", "0", "Debug-iphonesimulator", "BarTests.xctest"])
        )
        #expect(!siblingExists)
        let frameworkExists = try await fileSystem.exists(
            extractDir.appending(components: ["Binaries", "0", "Debug-iphonesimulator", "Shared.framework"])
        )
        #expect(!frameworkExists)
        let metadataExists = try await fileSystem.exists(extractDir.appending(component: "run-metadata.json"))
        #expect(!metadataExists)
    }
}
