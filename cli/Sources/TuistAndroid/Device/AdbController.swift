import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging

public enum AdbControllerError: LocalizedError, Equatable {
    case adbNotFound
    case noDevicesFound
    case installFailed(device: String, reason: String)
    case launchFailed(device: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb is required to run Android previews. Install it via the Android SDK (platform-tools) and ensure ANDROID_HOME or ANDROID_SDK_ROOT is set, or that adb is in your PATH."
        case .noDevicesFound:
            return "No Android devices or emulators found. Start an emulator or connect a device via USB."
        case let .installFailed(device, reason):
            return "Failed to install app on device \(device): \(reason)"
        case let .launchFailed(device, reason):
            return "Failed to launch app on device \(device): \(reason)"
        }
    }
}

@Mockable
public protocol AdbControlling: Sendable {
    func findAvailableDevices() async throws -> [AndroidDevice]
    func installApp(at path: AbsolutePath, device: AndroidDevice) async throws
    func launchApp(packageName: String, device: AndroidDevice) async throws
}

public struct AdbController: AdbControlling {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func findAvailableDevices() async throws -> [AndroidDevice] {
        let adb = try await resolveAdbPath()
        let output: String
        do {
            output = try await commandRunner
                .run(arguments: [adb, "devices", "-l"])
                .concatenatedString()
        } catch {
            throw AdbControllerError.adbNotFound
        }

        var devices: [AndroidDevice] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("List of devices"),
                  !trimmed.hasPrefix("*")
            else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let state = parts[1]

            guard state == "device" else { continue }

            let modelTag = parts.first(where: { $0.hasPrefix("model:") })
            let name = modelTag?.replacingOccurrences(of: "model:", with: "") ?? serial
            let isEmulator = serial.hasPrefix("emulator-")

            devices.append(AndroidDevice(id: serial, name: name, isEmulator: isEmulator))
        }

        return devices
    }

    public func installApp(at path: AbsolutePath, device: AndroidDevice) async throws {
        let adb = try await resolveAdbPath()
        do {
            try await commandRunner
                .run(arguments: [adb, "-s", device.id, "install", "-r", path.pathString])
                .awaitCompletion()
        } catch {
            throw AdbControllerError.installFailed(device: device.id, reason: Self.commandErrorMessage(error))
        }
    }

    public func launchApp(packageName: String, device: AndroidDevice) async throws {
        let adb = try await resolveAdbPath()
        let activity: String
        do {
            let output = try await commandRunner
                .run(arguments: [
                    adb, "-s", device.id, "shell",
                    "cmd", "package", "resolve-activity", "--brief",
                    "-a", "android.intent.action.MAIN",
                    "-c", "android.intent.category.LAUNCHER",
                    packageName,
                ])
                .concatenatedString()
            guard let lastLine = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .last,
                lastLine.contains("/")
            else {
                throw AdbControllerError.launchFailed(
                    device: device.id,
                    reason: "Could not resolve launcher activity for \(packageName)"
                )
            }
            activity = lastLine.trimmingCharacters(in: .whitespaces)
        } catch let error as AdbControllerError {
            throw error
        } catch {
            throw AdbControllerError.launchFailed(device: device.id, reason: Self.commandErrorMessage(error))
        }

        do {
            try await commandRunner
                .run(arguments: [
                    adb, "-s", device.id, "shell",
                    "am", "start", "-n", activity,
                ])
                .awaitCompletion()
        } catch {
            throw AdbControllerError.launchFailed(device: device.id, reason: Self.commandErrorMessage(error))
        }
    }

    // MARK: - Private

    private static func commandErrorMessage(_ error: Error) -> String {
        if let commandError = error as? CommandError {
            switch commandError {
            case let .terminated(code, stderr: stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Process exited with code \(code)"
                }
                return trimmed
            case let .signalled(code):
                return "Process terminated by signal \(code)"
            case let .executableNotFound(name):
                return "Executable '\(name)' not found"
            case .missingExecutableName:
                return "Missing executable name"
            }
        }
        return error.localizedDescription
    }

    /// The Android SDK doesn't add `platform-tools/` to `$PATH` by default, so `adb` is
    /// typically not directly invocable. We probe well-known SDK root locations — environment
    /// variables first (`ANDROID_HOME`, `ANDROID_SDK_ROOT`), then common install paths
    /// (mise, Android Studio, Homebrew) — and fall back to bare `adb` for the rare case
    /// where the user has added it to their PATH manually.
    private func resolveAdbPath() async throws -> String {
        var candidateRoots: [String] = []

        let variables = Environment.current.variables
        for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = variables[envVar], !value.isEmpty {
                candidateRoots.append(value)
            }
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? "~"
        candidateRoots.append(contentsOf: [
            "\(home)/.local/share/mise/installs/android-sdk/1.0",
            "\(home)/Library/Android/sdk",
            "/opt/homebrew/share/android-commandlinetools",
            "/usr/local/share/android-commandlinetools",
        ])

        for root in candidateRoots {
            let adbPath: AbsolutePath
            do {
                adbPath = try AbsolutePath(validating: root)
                    .appending(components: ["platform-tools", "adb"])
            } catch { continue }
            guard await (try? fileSystem.exists(adbPath)) == true else { continue }
            return adbPath.pathString
        }

        return "adb"
    }
}
