#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import Testing
    import TuistAndroid
    import TuistEnvironment
    import TuistProcess

    struct AdbControllerTests {
        private let commandRunner = MockCommandRunning()
        private let device = AndroidDevice(id: "emulator-5554", name: "Pixel", type: .emulator)

        @Test(arguments: [
            "com.example.app;reboot",
            "com.example.app$(id)",
            "com.example.app`id`",
            "com.example.app && input keyevent 3",
            "com.example.app\nreboot",
            "com.example.app|sh",
            "-a com.example.app",
            "com",
            "com..example",
            "1com.example",
            "com.example.",
            "com.1example",
        ])
        func launchApp_rejects_invalid_package_names_before_running_adb(packageName: String) async throws {
            let subject = AdbController(commandRunner: commandRunner)

            await #expect(throws: AdbControllerError.invalidPackageName(packageName)) {
                try await subject.launchApp(packageName: packageName, device: device)
            }
            verify(commandRunner).run(arguments: .any, environment: .any, workingDirectory: .any).called(0)
        }

        @Test(.inTemporaryDirectory) func launchApp_starts_the_resolved_launcher_activity() async throws {
            let adb = try await givenAdb(resolvingActivity: "com.example.my_app2/.MainActivity")

            try await withAndroidHome(adb) {
                try await AdbController(commandRunner: commandRunner).launchApp(
                    packageName: "com.example.my_app2",
                    device: device
                )
            }

            verify(commandRunner).run(
                arguments: .value([
                    adb.pathString, "-s", "emulator-5554", "shell", "am", "start", "-n", "com.example.my_app2/.MainActivity",
                ]),
                environment: .any,
                workingDirectory: .any
            ).called(1)
        }

        @Test(.inTemporaryDirectory, arguments: [
            "com.example.app/.Main;reboot",
            "com.example.app/.Main$(id)",
            "com.example.app.evil/.Main",
            "other.app/.Main",
        ])
        func launchApp_rejects_unexpected_launcher_activities(activity: String) async throws {
            let adb = try await givenAdb(resolvingActivity: activity)

            await #expect(throws: AdbControllerError.launchFailed(
                device: "emulator-5554",
                reason: "Unexpected launcher activity '\(activity)' for com.example.app"
            )) {
                try await withAndroidHome(adb) {
                    try await AdbController(commandRunner: commandRunner).launchApp(
                        packageName: "com.example.app",
                        device: device
                    )
                }
            }
            verify(commandRunner).run(
                arguments: .matching { $0.contains("am") },
                environment: .any,
                workingDirectory: .any
            ).called(0)
        }

        // MARK: - Helpers

        private func givenAdb(resolvingActivity activity: String) async throws -> AbsolutePath {
            let androidHome = try #require(FileSystem.temporaryTestDirectory)
            let adb = androidHome.appending(components: "platform-tools", "adb")
            try await FileSystem().makeDirectory(at: adb.parentDirectory)
            try await FileSystem().touch(adb)
            given(commandRunner)
                .run(arguments: .any, environment: .any, workingDirectory: .any)
                .willProduce { arguments, _, _ in
                    AsyncThrowingStream { continuation in
                        if arguments.contains("resolve-activity") {
                            continuation
                                .yield(ProcessEvent.standardOutput(Array("priority=0 preferredOrder=0\n\(activity)\n".utf8)))
                        }
                        continuation.finish()
                    }
                }
            return adb
        }

        private func withAndroidHome(_ adb: AbsolutePath, _ action: () async throws -> Void) async throws {
            let environment = Environment(variables: ["ANDROID_HOME": adb.parentDirectory.parentDirectory.pathString])
            try await Environment.$current.withValue(environment, operation: action)
        }
    }
#endif
