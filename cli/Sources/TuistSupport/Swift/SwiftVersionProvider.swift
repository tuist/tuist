import Command
import Foundation
import Mockable
import TuistEnvironment
import TuistLogging

public enum SwiftVersionProviderError: FatalError, Equatable {
    case parseSwiftVersion(String)
    case parseSwiftDefaultLanguageModeVersion(String)

    public var description: String {
        switch self {
        case let .parseSwiftVersion(output):
            return "Couldn't obtain the Swift version from the output: \(output)."
        case let .parseSwiftDefaultLanguageModeVersion(output):
            return "Couldn't obtain the default Swift language mode from the output: \(output)."
        }
    }

    public var type: ErrorType {
        .bug
    }
}

@Mockable
public protocol SwiftVersionProviding {
    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftVersion() async throws -> String

    /// Returns the Swift version, including the build number.
    ///
    /// - Returns: Swift version including the build number.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftlangVersion() async throws -> String

    /// Returns the language mode selected by `swift` when no language mode is specified,
    /// normalized for Xcode's `SWIFT_VERSION` build setting.
    func swiftDefaultLanguageModeVersion() async throws -> String
}

public struct SwiftVersionProvider: SwiftVersionProviding {
    @TaskLocal public static var current: SwiftVersionProviding = SwiftVersionProvider(commandRunner: CommandRunner())

    // Regex expression used to get the Swift version (for example, 5.9) from the output of the 'swift --version' command.
    // swiftlint:disable force_try
    private static let swiftVersionRegex = try! NSRegularExpression(
        pattern: "(?:Apple )?Swift version\\s([^\\s]+)", options: [.caseInsensitive]
    )

    // Regex expression used to get the Swiftlang version (for example, 5.7.0.127.4) from the output of the 'swift --version'
    // command.
    // swiftlint:disable force_try
    private static let swiftlangVersionRegex = try! NSRegularExpression(
        pattern: "swiftlang-(.+)\\sclang", options: []
    )

    // swiftlint:enable force_try

    static let swiftDefaultLanguageModeVersionProbe = """
    #if swift(>=6)
    print("6")
    #elseif swift(>=5)
    print("5")
    #elseif swift(>=4.2)
    print("4.2")
    #elseif swift(>=4)
    print("4")
    #else
    print("unsupported")
    #endif
    """

    private static let supportedSwiftDefaultLanguageModeVersions: Set<String> = ["4", "4.2", "5", "6"]

    public func swiftVersion() async throws -> String {
        try await cachedSwiftVersion.value()
    }

    public func swiftlangVersion() async throws -> String {
        try await cachedSwiftlangVersion.value()
    }

    public func swiftDefaultLanguageModeVersion() async throws -> String {
        try await cachedSwiftDefaultLanguageModeVersion.value()
    }

    private let cachedSwiftVersion: AsyncThrowableCaching<String>
    private let cachedSwiftlangVersion: AsyncThrowableCaching<String>
    private let cachedSwiftDefaultLanguageModeVersion: AsyncThrowableCaching<String>

    init(commandRunner: CommandRunning) {
        cachedSwiftVersion = AsyncThrowableCaching<String> {
            let output = try await commandRunner.capture(arguments: ["swift", "--version"])
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftVersionRegex.firstMatch(
                in: output, options: [], range: range
            )
            else {
                throw SwiftVersionProviderError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }

        cachedSwiftlangVersion = AsyncThrowableCaching<String> {
            let output = try await commandRunner.capture(arguments: ["swift", "--version"])
            let range = NSRange(location: 0, length: output.count)
            if let match = SwiftVersionProvider.swiftlangVersionRegex.firstMatch(
                in: output, options: [], range: range
            ) {
                return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
            }
            return output.spm_chomp()
        }

        cachedSwiftDefaultLanguageModeVersion = AsyncThrowableCaching<String> {
            let output = try await commandRunner.capture(
                arguments: ["swift", "-e", Self.swiftDefaultLanguageModeVersionProbe],
                environment: Environment.current.manifestLoadingVariables
            )
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.supportedSwiftDefaultLanguageModeVersions.contains(version) else {
                throw SwiftVersionProviderError.parseSwiftDefaultLanguageModeVersion(output)
            }
            return version
        }
    }
}
