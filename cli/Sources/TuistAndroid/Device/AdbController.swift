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
    func isAdbAvailable() async -> Bool
    func findAvailableDevices() async throws -> [AndroidDevice]
    func installApp(at path: AbsolutePath, device: AndroidDevice) async throws
    func launchApp(packageName: String, device: AndroidDevice) async throws
}

#if canImport(Command)
    import Command

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

        public func isAdbAvailable() async -> Bool {
            (try? await resolveAdbPath()) != nil
        }

        public func findAvailableDevices() async throws -> [AndroidDevice] {
            let adb = try await resolveAdbPath()
            let output: String
            do {
                output = try await commandRunner
                    .run(arguments: [adb.pathString, "devices", "-l"])
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
                let type: AndroidDevice.DeviceType = serial.hasPrefix("emulator-") ? .emulator : .device

                devices.append(AndroidDevice(id: serial, name: name, type: type))
            }

            return devices
        }

        public func installApp(at path: AbsolutePath, device: AndroidDevice) async throws {
            let adb = try await resolveAdbPath()
            do {
                try await commandRunner
                    .run(arguments: [adb.pathString, "-s", device.id, "install", "-r", path.pathString])
                    .awaitCompletion()
            } catch {
                throw AdbControllerError.installFailed(device: device.id, reason: error.localizedDescription)
            }
        }

        public func launchApp(packageName: String, device: AndroidDevice) async throws {
            let adb = try await resolveAdbPath()
            let output: String
            do {
                output = try await commandRunner
                    .run(arguments: [
                        adb.pathString, "-s", device.id, "shell",
                        "cmd", "package", "resolve-activity", "--brief",
                        "-a", "android.intent.action.MAIN",
                        "-c", "android.intent.category.LAUNCHER",
                        packageName,
                    ])
                    .concatenatedString()
            } catch {
                throw AdbControllerError.launchFailed(device: device.id, reason: error.localizedDescription)
            }

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
            let activity = lastLine.trimmingCharacters(in: .whitespaces)

            do {
                try await commandRunner
                    .run(arguments: [
                        adb.pathString, "-s", device.id, "shell",
                        "am", "start", "-n", activity,
                    ])
                    .awaitCompletion()
            } catch {
                throw AdbControllerError.launchFailed(device: device.id, reason: error.localizedDescription)
            }
        }

        // MARK: - Private

        private func resolveAdbPath() async throws -> AbsolutePath {
            let logger = Logger.current
            let variables = Environment.current.variables
            for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
                guard let value = variables[envVar], !value.isEmpty else { continue }
                let adbPath: AbsolutePath
                do {
                    adbPath = try AbsolutePath(validating: value)
                        .appending(components: ["platform-tools", "adb"])
                } catch { continue }
                if await (try? fileSystem.exists(adbPath)) == true {
                    logger.debug("Resolved adb path from \(envVar): \(adbPath.pathString)")
                    return adbPath
                }
            }

            let homeDir = Environment.current.homeDirectory
            let wellKnownPaths: [AbsolutePath] = [
                homeDir.appending(components: ["Library", "Android", "sdk", "platform-tools", "adb"]),
                homeDir.appending(
                    components: [".local", "share", "mise", "installs", "android-sdk", "latest", "platform-tools", "adb"]
                ),
                try AbsolutePath(validating: "/opt/homebrew/bin/adb"),
                try AbsolutePath(validating: "/usr/local/bin/adb"),
            ]
            for adbPath in wellKnownPaths {
                if await (try? fileSystem.exists(adbPath)) == true {
                    logger.debug("Resolved adb path: \(adbPath.pathString)")
                    return adbPath
                }
            }

            throw AdbControllerError.adbNotFound
        }
    }
#endif
