import Command
import FileSystem
import Foundation
import Path
import Testing

@testable import Rosalind

private struct TestCommandRunner: CommandRunning {
    let handler: @Sendable ([String]) -> AsyncThrowingStream<CommandEvent, any Error>

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        handler(arguments)
    }
}

private func commandOutput(_ output: String) -> AsyncThrowingStream<CommandEvent, any Error> {
    AsyncThrowingStream { continuation in
        continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
        continuation.finish()
    }
}

private func commandFailure(_ error: any Error) -> AsyncThrowingStream<CommandEvent, any Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}

struct AndroidBundleMetadataServiceTests {
    // MARK: - APK Metadata

    @Test func apkMetadata_parsesAllFields() async throws {
        let output = """
        package: name='com.example.app' versionCode='1' versionName='1.0.0'
        sdkVersion:'21'
        targetSdkVersion:'34'
        application-label:'My App'
        application-label-en:'My App'
        """
        let commandRunner = TestCommandRunner { arguments in
            commandOutput(arguments.contains("which") ? "/usr/bin/aapt2\n" : output)
        }
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        let metadata = try await subject.apkMetadata(at: path)

        #expect(metadata.packageName == "com.example.app")
        #expect(metadata.versionName == "1.0.0")
        #expect(metadata.appName == "My App")
    }

    @Test func apkMetadata_usesDefaults_whenOptionalFieldsMissing() async throws {
        let output = "package: name='com.example.app' versionCode='1'\n"
        let commandRunner = TestCommandRunner { arguments in
            commandOutput(arguments.contains("which") ? "/usr/bin/aapt2\n" : output)
        }
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        let metadata = try await subject.apkMetadata(at: path)

        #expect(metadata.packageName == "com.example.app")
        #expect(metadata.versionName == "1.0")
        #expect(metadata.appName == "com.example.app")
    }

    @Test func apkMetadata_throws_whenPackageNameMissing() async throws {
        let output = "sdkVersion:'21'\ntargetSdkVersion:'34'\n"
        let commandRunner = TestCommandRunner { arguments in
            commandOutput(arguments.contains("which") ? "/usr/bin/aapt2\n" : output)
        }
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        await #expect {
            try await subject.apkMetadata(at: path)
        } throws: { error in
            if let e = error as? AndroidBundleMetadataServiceError, case .parsingFailed = e { return true }
            return false
        }
    }

    /// With pool capacity 1, a leaked lock after `dump badging` fails would block the next `apkMetadata` on `acquire`.
    @Test func apkMetadata_returnsMetadataForSecondPath_afterFirstPathCommandFails_whenPoolCapacityIsOne() async throws {
        let failingPath = try AbsolutePath(validating: "/path/to/failing.apk")
        let okPath = try AbsolutePath(validating: "/path/to/ok.apk")
        let commandError = CommandError.terminated(1, stderr: "badging failed", command: [])
        let isolatedLock = PoolLock(capacity: 1)

        let okOutput = """
        package: name='com.example.app' versionCode='1' versionName='1.0.0'
        sdkVersion:'21'
        application-label:'My App'
        """
        let commandRunner = TestCommandRunner { arguments in
            if arguments.contains("which") {
                return commandOutput("/usr/bin/aapt2\n")
            }
            if arguments.contains(failingPath.pathString) {
                return commandFailure(commandError)
            }
            return commandOutput(okOutput)
        }
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)

        try await AndroidBundleMetadataService.$poolLock.withValue(isolatedLock) {
            await #expect {
                try await subject.apkMetadata(at: failingPath)
            } throws: { error in
                if let commandError = error as? CommandError,
                   case let .terminated(code, stderr, _) = commandError
                {
                    return code == 1 && stderr == "badging failed"
                }
                return false
            }

            let metadata = try await subject.apkMetadata(at: okPath)

            #expect(metadata.packageName == "com.example.app")
            #expect(metadata.versionName == "1.0.0")
            #expect(metadata.appName == "My App")
        }
    }

    // MARK: - AAB Metadata

    @Test func aabMetadata_resolvesTheLabelReference_whenADependencyShipsItsOwnAppNameString() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)
        let aabPath = try fixturePath("android_app/app.aab")

        let metadata = try await subject.aabMetadata(at: aabPath)

        #expect(metadata.packageName == "dev.tuist.example")
        #expect(metadata.versionName == "1.0")
        #expect(metadata.appName == "Simple Android App")
    }

    @Test func aabMetadata_usesTheLiteralLabel_whenTheLabelIsNotAResourceReference() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)
        let aabPath = try fixturePath("android_app/app-with-literal-label.aab")

        let metadata = try await subject.aabMetadata(at: aabPath)

        #expect(metadata.appName == "Literal Android App")
    }

    @Test func aabMetadata_fallsBackToThePackageName_whenThereIsNoLabel() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)
        let aabPath = try fixturePath("android_app/app-without-label.aab")

        let metadata = try await subject.aabMetadata(at: aabPath)

        #expect(metadata.appName == "dev.tuist.example")
    }

    @Test func aabMetadata_throws_whenManifestNotFound() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabContentsPath = temporaryDirectory.appending(component: "aab-contents")
            let basePath = aabContentsPath.appending(component: "base")
            try await fileSystem.makeDirectory(at: basePath)
            try await fileSystem.writeText("content", at: basePath.appending(component: "dummy.txt"))

            let aabPath = temporaryDirectory.appending(component: "app.aab")
            try await fileSystem.zipFileOrDirectoryContent(at: aabContentsPath, to: aabPath)

            await #expect {
                try await subject.aabMetadata(at: aabPath)
            } throws: { error in
                if let e = error as? AndroidBundleMetadataServiceError, case .manifestNotFound = e { return true }
                return false
            }
        }
    }

    // MARK: - AAB Metadata from already-extracted contents

    @Test func aabMetadata_fromExtractedContents_readsMetadataWithoutUnzipping() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)
        let aabPath = try fixturePath("android_app/app.aab")

        try await fileSystem.runInTemporaryDirectory(prefix: "extracted") { temporaryDirectory in
            let extractedPath = temporaryDirectory.appending(component: "extracted")
            try await fileSystem.unzip(aabPath, to: extractedPath)

            let metadata = try await subject.aabMetadata(fromExtractedContentsAt: extractedPath)

            #expect(metadata.packageName == "dev.tuist.example")
            #expect(metadata.versionName == "1.0")
            #expect(metadata.appName == "Simple Android App")
        }
    }

    @Test func aabMetadata_fromExtractedContents_throws_whenManifestNotFound() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "extracted") { temporaryDirectory in
            let extractedPath = temporaryDirectory.appending(component: "extracted")
            try await fileSystem.makeDirectory(at: extractedPath.appending(component: "base"))

            await #expect {
                try await subject.aabMetadata(fromExtractedContentsAt: extractedPath)
            } throws: { error in
                if let e = error as? AndroidBundleMetadataServiceError, case .manifestNotFound = e { return true }
                return false
            }
        }
    }

    // MARK: - Helpers

    private func fixturePath(_ relativePath: String) throws -> AbsolutePath {
        try AbsolutePath(validating: "\(#filePath)")
            .parentDirectory.parentDirectory
            .appending(components: "Fixtures", "Rosalind")
            .appending(try RelativePath(validating: relativePath))
    }
}
