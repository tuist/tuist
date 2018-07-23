import Basic
import Foundation
import SwiftShell

public protocol Systeming {
    func capture2(args: [String]) -> System2Result
    func capture2(args: String...) -> System2Result
    func capture2e(args: [String]) -> System2eResult
    func capture2e(args: String...) -> System2eResult
    func capture3(args: [String]) -> System3Result
    func capture3(args: String...) -> System3Result
}

struct SystemError: FatalError {
    let stderror: String?
    let exitcode: Int

    var type: ErrorType {
        return .abort
    }

    var description: String {
        return stderror ?? "Error running command."
    }
}

public struct System3Result {
    public let stdout: String
    public let stderror: String
    public let exitcode: Int
    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: stderror, exitcode: exitcode) }
    }
}

public struct System2eResult {
    public let std: String
    public let exitcode: Int
    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: nil, exitcode: exitcode) }
    }
}

public struct System2Result {
    public let stdout: String
    public let exitcode: Int
    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: nil, exitcode: exitcode) }
    }
}

public final class System: Systeming {
    public init() {}

    public func capture2(args: String...) -> System2Result {
        return capture2(args: args)
    }

    public func capture2(args: [String]) -> System2Result {
        precondition(args.count >= 1, "Invalid number of argumentss")
        var args = args

        var result: RunOutput!

        if args.count == 1 {
            result = run(bash: args.first!, combineOutput: false)
        } else {
            let executable = args.first!
            args = args.dropFirst().map({ $0.shellEscaped() })
            result = run(executable, args, combineOutput: false)
        }
        return System2Result(stdout: result.stdout, exitcode: result.exitcode)
    }

    public func capture2e(args: String...) -> System2eResult {
        return capture2e(args: args)
    }

    public func capture2e(args: [String]) -> System2eResult {
        precondition(args.count >= 1, "Invalid number of argumentss")
        var args = args

        var result: RunOutput!

        if args.count == 1 {
            result = run(bash: args.first!, combineOutput: true)
        } else {
            let executable = args.first!
            args = args.dropFirst().map({ $0.shellEscaped() })
            result = run(executable, args, combineOutput: true)
        }

        return System2eResult(std: result.stdout, exitcode: result.exitcode)
    }

    public func capture3(args: String...) -> System3Result {
        return capture3(args: args)
    }

    public func capture3(args: [String]) -> System3Result {
        precondition(args.count >= 1, "Invalid number of argumentss")
        var args = args

        var result: RunOutput!

        if args.count == 1 {
            result = run(bash: args.first!, combineOutput: false)
        } else {
            let executable = args.first!
            args = args.dropFirst().map({ $0.shellEscaped() })
            result = run(executable, args, combineOutput: false)
        }

        return System3Result(stdout: result.stdout, stderror: result.stderror, exitcode: result.exitcode)
    }
}
