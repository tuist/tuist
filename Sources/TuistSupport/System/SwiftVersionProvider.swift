import Foundation
import Mockable

@Mockable
public protocol SwiftVersionProviding {
    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftVersion() throws -> String

    /// Returns the Swift version, including the build number.
    ///
    /// - Returns: Swift version including the build number.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftlangVersion() throws -> String
}

public final class SwiftVersionProvider: SwiftVersionProviding {
    public static var shared: SwiftVersionProviding {
        _shared.value
    }

    // swiftlint:disable:next identifier_name
    static let _shared: ThreadSafe<SwiftVersionProviding> = ThreadSafe(SwiftVersionProvider(System.shared))
    // swiftlint:disable force_try

    /// Regex expression used to get the Swift version (for example, 5.9) from the output of the 'swift --version' command.
    private static let swiftVersionRegex = try! NSRegularExpression(pattern: "Apple Swift version\\s(.+)\\s\\(.+\\)", options: [])

    /// Regex expression used to get the Swiftlang version (for example, 5.7.0.127.4) from the output of the 'swift --version'
    /// command.
    private static let swiftlangVersionRegex = try! NSRegularExpression(pattern: "swiftlang-(.+)\\sclang", options: [])

    // swiftlint:enable force_try

    public func swiftVersion() throws -> String {
        try cachedSwiftVersion.value
    }

    public func swiftlangVersion() throws -> String {
        try cachedSwiftlangVersion.value
    }

    let cachedSwiftVersion: ThrowableCaching<String>
    let cachedSwiftlangVersion: ThrowableCaching<String>

    init(_ system: Systeming) {
        cachedSwiftVersion = ThrowableCaching<String> {
            let output = try system.capture(["/usr/bin/xcrun", "swift", "--version"])
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftVersionRegex.firstMatch(in: output, options: [], range: range) else {
                throw SystemError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }

        cachedSwiftlangVersion = ThrowableCaching<String> {
            let output = try system.capture(["/usr/bin/xcrun", "swift", "--version"])
            let range = NSRange(location: 0, length: output.count)
            guard let match = SwiftVersionProvider.swiftlangVersionRegex.firstMatch(in: output, options: [], range: range) else {
                throw SystemError.parseSwiftVersion(output)
            }
            return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
        }
    }
}
