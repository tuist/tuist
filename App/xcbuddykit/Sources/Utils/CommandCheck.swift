import Foundation
import Utility

/// Command check errors.
///
/// - swiftVersionNotFound: Thrown when the Swift version cannot be determined.
/// - incompatibleSwiftVersion: Thrown when the version of Swift in the system is incompatible with the version of the precompiled frameworks.
enum CommandCheckError: FatalError, Equatable {
    case swiftVersionNotFound
    case incompatibleSwiftVersion(system: String, expected: String)
    var description: String {
        switch self {
        case .swiftVersionNotFound:
            var message = "Error getting your Swift version."
            message.append(" Make sure 'swift' is available from your shell and that 'swift version' returns the language version")
            return message
        case let .incompatibleSwiftVersion(system, expected):
            var message = "The Swift version in your system, \(system) is incompatible with the version xcbuddy expects \(expected)"
            message.append(" If you updated Xcode recently, update xcbuddy to the lastest version.")
            return message
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .incompatibleSwiftVersion: fallthrough
        case .swiftVersionNotFound:
            return .abort
        }
    }

    /// Returns true if two instances of the error are equal to each other.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if both are equal
    static func == (lhs: CommandCheckError, rhs: CommandCheckError) -> Bool {
        switch (lhs, rhs) {
        case (.swiftVersionNotFound, .swiftVersionNotFound): return true
        case let (.incompatibleSwiftVersion(lhsSystem, lhsExpected),
                  .incompatibleSwiftVersion(rhsSystem, rhsExpected)):
            return lhsSystem == rhsSystem && lhsExpected == rhsExpected
        default:
            return false
        }
    }
}

/// A protocol that defines a check that can be executed before running commands.
protocol CommandChecking: AnyObject {
    /// Executes the startup checks.
    ///
    /// - Throws: throws if the tool cannot continue because certain requirements are not med.
    func check(command: String) throws
}

/// Class that executes some checks before running any command.
final class CommandCheck: CommandChecking {
    /// Context.
    let context: Contexting

    /// Initializes the startup check with a context.
    ///
    /// - Parameter context: context.
    init(context: Contexting = Context()) {
        self.context = context
    }

    /// Executes some checks at startup.
    ///
    /// - Throws: an error if any of the checks fails.
    func check(command: String) throws {
        if !CommandCheck.checkableCommands().contains(command) { return }
        try swiftVersionCompatibility()
    }

    /// Throws if the Swift version the frameworks have been compiled with doesn't match the version in the system.
    /// This won't be needed anymore after the ABI stability gets introduced.
    ///
    /// - Throws: an error if the versions don't match.
    func swiftVersionCompatibility() throws {
        let output = try context.shell.run("swift", "--version").chomp()
        let regex = try NSRegularExpression(pattern: "Apple\\sSwift\\sversion\\s(\\d+\\.\\d+(\\.\\d+)?)", options: [])
        guard let versionMatch = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.count)) else {
            throw CommandCheckError.swiftVersionNotFound
        }
        let versionRange = versionMatch.range(at: 1)
        let currentVersion: String = (output as NSString).substring(with: versionRange)
        if currentVersion != Constants.swiftVersion {
            throw CommandCheckError.incompatibleSwiftVersion(system: currentVersion, expected: Constants.swiftVersion)
        }
    }

    /// Returns the list of commands that should be checked.
    ///
    /// - Returns: list of commands that should be checked.
    static func checkableCommands() -> [String] {
        return [
            DumpCommand.command,
            GenerateCommand.command,
        ]
    }
}
