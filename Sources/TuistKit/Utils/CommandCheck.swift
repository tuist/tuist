import Foundation
import SPMUtility
import TuistCore

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
            var message = "The Swift version in your system, \(system) is incompatible with the version tuist expects \(expected)"
            message.append(" If you updated Xcode recently, update tuist to the lastest version.")
            return message
        }
    }

    var type: ErrorType {
        switch self {
        case .incompatibleSwiftVersion, .swiftVersionNotFound:
            return .abort
        }
    }

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

protocol CommandChecking: AnyObject {
    func check(command: String) throws
}

final class CommandCheck: CommandChecking {
    // MARK: - Attributes

    let system: Systeming

    // MARK: - Init

    init(system: Systeming = System()) {
        self.system = system
    }

    // MARK: - CommandChecking

    func check(command: String) throws {
        if !CommandCheck.checkableCommands().contains(command) { return }
//        try swiftVersionCompatibility()
    }

//    func swiftVersionCompatibility() throws {
//        let output = try system.capture("xcrun", "swift", "--version", verbose: false).throwIfError().stdout.chuzzle() ?? ""
//        let regex = try NSRegularExpression(pattern: "Apple\\sSwift\\sversion\\s(\\d+\\.\\d+(\\.\\d+)?)", options: [])
//        guard let versionMatch = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.count)) else {
//            throw CommandCheckError.swiftVersionNotFound
//        }
//        let versionRange = versionMatch.range(at: 1)
//        let currentVersion: String = (output as NSString).substring(with: versionRange)
//        if currentVersion != Constants.swiftVersion() {
//            throw CommandCheckError.incompatibleSwiftVersion(system: currentVersion, expected: Constants.swiftVersion())
//        }
//    }

    static func checkableCommands() -> [String] {
        return [
            DumpCommand.command,
            GenerateCommand.command,
        ]
    }
}
