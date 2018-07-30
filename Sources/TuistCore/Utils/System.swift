import Basic
import Foundation
import SwiftShell

var runningCommand: AsyncCommand?

public protocol Systeming {
    func capture2(_ args: [String], verbose: Bool) -> System2Result
    func capture2(_ args: String..., verbose: Bool) -> System2Result
    func capture2e(_ args: [String], verbose: Bool) -> System2eResult
    func capture2e(_ args: String..., verbose: Bool) -> System2eResult
    func capture3(_ args: [String], verbose: Bool) -> System3Result
    func capture3(_ args: String..., verbose: Bool) -> System3Result
    func popen(_ args: String..., printing: Bool, verbose: Bool, onOutput: ((String) -> Void)?, onError: ((String) -> Void)?, onCompletion: ((Int) -> Void)?) throws
    func popen(_ args: [String], printing: Bool, verbose: Bool, onOutput: ((String) -> Void)?, onError: ((String) -> Void)?, onCompletion: ((Int) -> Void)?) throws
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
    public init(stdout: String, stderror: String, exitcode: Int) {
        self.stdout = stdout
        self.stderror = stderror
        self.exitcode = exitcode
    }

    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: stderror, exitcode: exitcode) }
    }
}

public struct System2eResult {
    public let std: String
    public let exitcode: Int
    public init(std: String, exitcode: Int) {
        self.std = std
        self.exitcode = exitcode
    }

    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: nil, exitcode: exitcode) }
    }
}

public struct System2Result {
    public let stdout: String
    public let exitcode: Int
    public init(stdout: String, exitcode: Int) {
        self.stdout = stdout
        self.exitcode = exitcode
    }

    public func throwIfError() throws {
        if exitcode != 0 { throw SystemError(stderror: nil, exitcode: exitcode) }
    }
}

public final class System: Systeming {
    let printer: Printing

    public init(printer: Printing = Printer()) {
        self.printer = printer
    }

    // MARK: - Systeming

    public func capture2(_ args: String..., verbose: Bool = false) -> System2Result {
        return capture2(args, verbose: verbose)
    }

    public func capture2(_ args: [String], verbose _: Bool = false) -> System2Result {
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

    public func capture2e(_ args: String..., verbose: Bool = false) -> System2eResult {
        return capture2e(args, verbose: verbose)
    }

    public func capture2e(_ args: [String], verbose _: Bool = false) -> System2eResult {
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

    public func capture3(_ args: String..., verbose: Bool = false) -> System3Result {
        return capture3(args, verbose: verbose)
    }

    public func capture3(_ args: [String], verbose _: Bool = false) -> System3Result {
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

    public func popen(_ args: String...,
                      printing: Bool = false,
                      verbose: Bool = false,
                      onOutput: ((String) -> Void)? = nil,
                      onError: ((String) -> Void)? = nil,
                      onCompletion: ((Int) -> Void)? = nil) throws {
        try popen(args,
              printing: printing,
              verbose: verbose,
              onOutput: onOutput,
              onError: onError,
              onCompletion: onCompletion)
    }

    public func popen(_ args: [String],
                      printing: Bool = false,
                      verbose _: Bool = false,
                      onOutput: ((String) -> Void)? = nil,
                      onError: ((String) -> Void)? = nil,
                      onCompletion: ((Int) -> Void)? = nil) throws {
        precondition(args.count >= 1, "Invalid number of argumentss")

        var args = args
        var command: PrintedAsyncCommand!

        if args.count == 1 {
            command = runAsync(args.first!)
        } else {
            let executable = args.first!
            args = args.dropFirst().map({ $0.shellEscaped() })
            command = runAsyncAndPrint(executable, args)
        }
//        command.onCompletion {
//            Swift.print("xx")
//            onCompletion?($0.exitcode())
//        }
//        command.stdout.onStringOutput {
//            Swift.print("xx")
//            if printing { FileHandle.standardOutput.write($0) }
//            onOutput?($0)
//        }
//        command.stderror.onStringOutput {
//            Swift.print("xx")
//            if printing { FileHandle.standardError.write($0) }
//            onError?($0)
//        }
        
        try command.launch()
    }

    // MARK: - Fileprivate

    fileprivate func print(command: [String]) {
        printer.print(command.joined(separator: " "))
    }
}
