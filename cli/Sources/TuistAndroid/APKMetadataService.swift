import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment

public enum APKMetadataServiceError: LocalizedError, Equatable {
    case aapt2NotFound
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .aapt2NotFound:
            return "aapt2 is required to read APK metadata. Install it via the Android SDK (build-tools) and ensure ANDROID_HOME or ANDROID_SDK_ROOT is set, or that aapt2 is in your PATH."
        case let .parsingFailed(path):
            return "Failed to parse APK metadata from \(path). Ensure the file is a valid APK."
        }
    }
}

@Mockable
public protocol APKMetadataServicing {
    func parseMetadata(at apkPath: AbsolutePath) async throws -> APKMetadata
}

#if canImport(Command)
    import Command

    public struct APKMetadataService: APKMetadataServicing {
        private let fileSystem: FileSysteming
        private let commandRunner: CommandRunning

        public init(
            fileSystem: FileSysteming = FileSystem(),
            commandRunner: CommandRunning = CommandRunner()
        ) {
            self.fileSystem = fileSystem
            self.commandRunner = commandRunner
        }

        public func parseMetadata(at apkPath: AbsolutePath) async throws -> APKMetadata {
            let aapt2 = try await resolveAapt2Path()

            let output: String
            do {
                output = try await commandRunner
                    .run(arguments: [aapt2, "dump", "badging", apkPath.pathString])
                    .concatenatedString()
            } catch {
                throw APKMetadataServiceError.aapt2NotFound
            }

            var packageName: String?
            var versionName: String?
            var versionCode: String?
            var applicationLabel: String?
            var iconPaths: [(density: String, path: String)] = []

            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("package:") {
                    packageName = extractValue(from: line, key: "name")
                    versionCode = extractValue(from: line, key: "versionCode")
                    versionName = extractValue(from: line, key: "versionName")
                } else if line.hasPrefix("application-label:") {
                    applicationLabel = line
                        .replacingOccurrences(of: "application-label:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                } else if line.hasPrefix("application-icon-") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let density = String(parts[0]).replacingOccurrences(of: "application-icon-", with: "")
                    let path = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                    if !path.isEmpty {
                        iconPaths.append((density: density, path: path))
                    }
                }
            }

            guard let packageName, let versionName, let versionCode else {
                throw APKMetadataServiceError.parsingFailed(apkPath.pathString)
            }

            let iconPath = try bestIconPath(from: iconPaths)
                .map { try RelativePath(validating: $0) }

            return APKMetadata(
                packageName: packageName,
                versionName: versionName,
                versionCode: versionCode,
                displayName: applicationLabel ?? apkPath.basenameWithoutExt,
                iconPath: iconPath
            )
        }

        private let densityPriority = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", "ldpi"]

        private func bestIconPath(from iconPaths: [(density: String, path: String)]) -> String? {
            guard !iconPaths.isEmpty else { return nil }
            for density in densityPriority {
                if let match = iconPaths.first(where: { $0.density == density }) {
                    return match.path
                }
            }
            return iconPaths.first?.path
        }

        private func resolveAapt2Path() async throws -> String {
            let variables = Environment.current.variables
            for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
                guard let value = variables[envVar], !value.isEmpty else { continue }
                let buildToolsDir: AbsolutePath
                do {
                    buildToolsDir = try AbsolutePath(validating: value).appending(component: "build-tools")
                } catch { continue }
                guard await (try? fileSystem.exists(buildToolsDir)) == true else { continue }
                let aapt2Paths = try await fileSystem.glob(directory: buildToolsDir, include: ["*/aapt2"]).collect()
                if let aapt2 = aapt2Paths.sorted(by: { $0.pathString > $1.pathString }).first {
                    return aapt2.pathString
                }
            }
            return "aapt2"
        }

        private func extractValue(from line: String, key: String) -> String? {
            guard let range = line.range(of: "\(key)='") else { return nil }
            let start = range.upperBound
            guard let end = line[start...].firstIndex(of: "'") else { return nil }
            return String(line[start ..< end])
        }
    }
#endif
