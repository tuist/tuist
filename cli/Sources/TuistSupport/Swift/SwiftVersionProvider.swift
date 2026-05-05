import Command
import Foundation
import Mockable
import TuistLogging

public enum SwiftVersionProviderError: FatalError, Equatable {
    case parseSwiftVersion(String)

    public var description: String {
        switch self {
        case let .parseSwiftVersion(output):
            return "Couldn't obtain the Swift version from the output: \(output)."
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
}

public struct SwiftVersionProvider: SwiftVersionProviding {
    @TaskLocal public static var current: SwiftVersionProviding = SwiftVersionProvider(commandRunner: CommandRunner())

    // Regex expression used to get the Swift version (for example, 5.9) from the output of the 'swift --version' command.
    // swiftlint:disable force_try
    private static let swiftVersionRegex = try! NSRegularExpression(
        pattern: "Apple Swift version\\s(.+)\\s\\(.+\\)", options: []
    )

    // Regex expression used to get the Swiftlang version (for example, 5.7.0.127.4) from the output of the 'swift --version'
    // command.
    // swiftlint:disable force_try
    private static let swiftlangVersionRegex = try! NSRegularExpression(
        pattern: "swiftlang-(.+)\\sclang", options: []
    )

    // swiftlint:enable force_try

    public func swiftVersion() async throws -> String {
        try await cachedSwiftVersion.value()
    }

    public func swiftlangVersion() async throws -> String {
        try await cachedSwiftlangVersion.value()
    }

    private let cachedSwiftVersion: AsyncThrowableCaching<String>
    private let cachedSwiftlangVersion: AsyncThrowableCaching<String>

    init(commandRunner: CommandRunning) {
        cachedSwiftVersion = AsyncThrowableCaching<String> {
            let output = try await commandRunner.capture(arguments: ["/usr/bin/xcrun", "swift", "--version"])
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
            let output = try await commandRunner.capture(arguments: ["/usr/bin/xcrun", "swift", "--version"])
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftlangVersionRegex.firstMatch(
                in: output, options: [], range: range
            )
            else {
                throw SwiftVersionProviderError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }
    }
}

private actor AsyncThrowableCaching<T: Sendable> {
    private var cachedValue: T?
    private let builder: @Sendable () async throws -> T

    init(_ builder: @Sendable @escaping () async throws -> T) {
        self.builder = builder
    }

    func value() async throws -> T {
        if let cachedValue {
            return cachedValue
        }
        let realizedValue = try await builder()
        cachedValue = realizedValue
        return realizedValue
    }
}
