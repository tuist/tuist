import Command
import Foundation
import Mockable

@Mockable
public protocol SwiftVersionProviding {
    func swiftVersion() async throws -> String
    func swiftlangVersion() async throws -> String
}

public struct SwiftVersionProvider: SwiftVersionProviding {
    @TaskLocal public static var current: SwiftVersionProviding = SwiftVersionProvider()

    // swiftlint:disable force_try
    private static let swiftVersionRegex = try! NSRegularExpression(
        pattern: "Apple Swift version\\s(.+)\\s\\(.+\\)", options: []
    )

    private static let swiftlangVersionRegex = try! NSRegularExpression(
        pattern: "swiftlang-(.+)\\sclang", options: []
    )

    // swiftlint:enable force_try

    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func swiftVersion() async throws -> String {
        try await cachedSwiftVersion.value()
    }

    public func swiftlangVersion() async throws -> String {
        try await cachedSwiftlangVersion.value()
    }

    private var cachedSwiftVersion: AsyncThrowableCaching<String> {
        AsyncThrowableCaching<String> { [commandRunner] in
            let output = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "swift", "--version"])
                .concatenatedString()
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftVersionRegex.firstMatch(
                in: output, options: [], range: range
            )
            else {
                throw SystemError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }
    }

    private var cachedSwiftlangVersion: AsyncThrowableCaching<String> {
        AsyncThrowableCaching<String> { [commandRunner] in
            let output = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "swift", "--version"])
                .concatenatedString()
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftlangVersionRegex.firstMatch(
                in: output, options: [], range: range
            )
            else {
                throw SystemError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }
    }
}

private struct AsyncThrowableCaching<T: Sendable>: Sendable {
    let closure: @Sendable () async throws -> T
    func value() async throws -> T {
        try await closure()
    }
}
