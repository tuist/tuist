#if os(macOS)
    import Command
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import Testing
    import TuistAndroid

    struct APKMetadataServiceTests {
        private let subject: APKMetadataService
        private let commandRunner = MockCommandRunning()

        init() {
            subject = APKMetadataService(
                commandRunner: commandRunner
            )
        }

        @Test(.inTemporaryDirectory) func parseMetadata_parses_all_fields() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try Data().write(to: URL(fileURLWithPath: apkPath.pathString))

            let output = """
            package: name='com.example.myapp' versionCode='42' versionName='1.2.3' compileSdkVersion='34'
            application-label:'My Cool App'
            application-icon-mdpi:'res/mipmap-mdpi-v4/ic_launcher.png'
            application-icon-hdpi:'res/mipmap-hdpi-v4/ic_launcher.png'
            application-icon-xhdpi:'res/mipmap-xhdpi-v4/ic_launcher.png'
            application-icon-xxhdpi:'res/mipmap-xxhdpi-v4/ic_launcher.png'
            application-icon-xxxhdpi:'res/mipmap-xxxhdpi-v4/ic_launcher.png'
            """

            givenAapt2Output(output)

            let metadata = try await subject.parseMetadata(at: apkPath)

            #expect(metadata.packageName == "com.example.myapp")
            #expect(metadata.versionName == "1.2.3")
            #expect(metadata.versionCode == "42")
            #expect(metadata.displayName == "My Cool App")
            let expectedIcon = try RelativePath(validating: "res/mipmap-xxxhdpi-v4/ic_launcher.png")
            #expect(metadata.iconPath == expectedIcon)
        }

        @Test(.inTemporaryDirectory) func parseMetadata_picks_highest_density_icon() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try Data().write(to: URL(fileURLWithPath: apkPath.pathString))

            let output = """
            package: name='com.example.app' versionCode='1' versionName='1.0'
            application-label:'App'
            application-icon-mdpi:'res/mipmap-mdpi/ic_launcher.png'
            application-icon-xhdpi:'res/mipmap-xhdpi/ic_launcher.png'
            """

            givenAapt2Output(output)

            let metadata = try await subject.parseMetadata(at: apkPath)

            let expectedIcon = try RelativePath(validating: "res/mipmap-xhdpi/ic_launcher.png")
            #expect(metadata.iconPath == expectedIcon)
        }

        @Test(.inTemporaryDirectory) func parseMetadata_returns_nil_icon_when_no_icon_lines() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try Data().write(to: URL(fileURLWithPath: apkPath.pathString))

            let output = """
            package: name='com.example.app' versionCode='1' versionName='1.0'
            application-label:'App'
            """

            givenAapt2Output(output)

            let metadata = try await subject.parseMetadata(at: apkPath)

            #expect(metadata.iconPath == nil)
        }

        @Test(.inTemporaryDirectory) func parseMetadata_throws_when_required_fields_missing() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try Data().write(to: URL(fileURLWithPath: apkPath.pathString))

            let output = """
            application-label:'App'
            """

            givenAapt2Output(output)

            await #expect(throws: APKMetadataServiceError.parsingFailed(apkPath.pathString)) {
                try await subject.parseMetadata(at: apkPath)
            }
        }

        @Test(.inTemporaryDirectory) func parseMetadata_uses_filename_when_no_label() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let apkPath = temporaryDirectory.appending(component: "MyApp.apk")
            try Data().write(to: URL(fileURLWithPath: apkPath.pathString))

            let output = """
            package: name='com.example.app' versionCode='1' versionName='1.0'
            """

            givenAapt2Output(output)

            let metadata = try await subject.parseMetadata(at: apkPath)

            #expect(metadata.displayName == "MyApp")
        }

        // MARK: - Helpers

        private func givenAapt2Output(_ output: String) {
            given(commandRunner)
                .run(
                    arguments: .any,
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
                        continuation.finish()
                    }
                )
        }
    }
#endif
