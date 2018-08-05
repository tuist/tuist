import Basic
import Foundation

public protocol Systeming {
    func capture(_ args: [String], verbose: Bool) throws -> SystemResult
    func capture(_ args: String..., verbose: Bool) throws -> SystemResult
    func popen(_ args: String..., verbose: Bool) throws
    func popen(_ args: [String], verbose: Bool) throws
}

public struct SystemError: FatalError {
    let stderror: String?
    let exitcode: Int32

    public var type: ErrorType {
        return .abort
    }

    public var description: String {
        return stderror ?? "Error running command"
    }

    public init(stderror: String? = nil, exitcode: Int32) {
        self.stderror = stderror
        self.exitcode = exitcode
    }
}

public struct SystemResult {
    public let stdout: String
    public let stderror: String
    public let exitcode: Int32
    public init(stdout: String, stderror: String, exitcode: Int32) {
        self.stdout = stdout
        self.stderror = stderror
        self.exitcode = exitcode
    }

    @discardableResult
    public func throwIfError() throws -> SystemResult {
        if exitcode != 0 { throw SystemError(stderror: stderror, exitcode: exitcode) }
        return self
    }
}

extension ProcessResult.ExitStatus {
    var code: Int32 {
        switch self {
        case let .signalled(code): return code
        case let .terminated(code): return code
        }
    }
}

extension ProcessResult {
    func result() throws -> SystemResult {
        return SystemResult(stdout: try utf8Output(),
                            stderror: try utf8stderrOutput(),
                            exitcode: exitStatus.code)
    }
}

public final class System: Systeming {

    // MARK: - Attributes

    let printer: Printing

    // MARK: - Init

    public init(printer: Printing = Printer()) {
        self.printer = printer
    }

    // MARK: - Systeming

    @discardableResult
    public func capture(_ args: String..., verbose: Bool = false) throws -> SystemResult {
        return try capture(args, verbose: verbose)
    }

    @discardableResult
    public func capture(_ args: [String], verbose: Bool = false) throws -> SystemResult {
        precondition(args.count >= 1, "Invalid number of argumentss")
        let process = Process(arguments: ["/bin/bash", "-c", args.joined(separator: " ")], redirectOutput: true, verbose: verbose)
        try process.launch()
        return try process.waitUntilExit().result()
    }

    public func popen(_ args: String..., verbose: Bool = false) throws {
        try popen(args, verbose: verbose)
    }

    public func popen(_ args: [String], verbose: Bool = false) throws {
        precondition(args.count >= 1, "Invalid number of arguments")
        let process = Process(arguments: ["/bin/bash", "-c", args.joined(separator: " ")], redirectOutput: false, verbose: verbose)
        try process.launch()
        try process.waitUntilExit().result().throwIfError()
    }

    // MARK: - Fileprivate

    fileprivate func print(command: [String]) {
        printer.print(command.joined(separator: " "))
    }
}
