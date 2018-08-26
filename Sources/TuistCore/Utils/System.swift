import Basic
import Foundation
import ReactiveSwift
import ReactiveTask

public protocol Systeming {
    func capture(_ args: [String], verbose: Bool) throws -> SystemResult
    func capture(_ args: String..., verbose: Bool) throws -> SystemResult
    func popen(_ args: String..., verbose: Bool) throws
    func popen(_ args: [String], verbose: Bool) throws
}

public struct SystemError: FatalError, Equatable {
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

    public static func == (lhs: SystemError, rhs: SystemError) -> Bool {
        return lhs.stderror == rhs.stderror &&
            lhs.exitcode == rhs.exitcode
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
    public func capture(_ args: [String], verbose _: Bool = false) throws -> SystemResult {
        precondition(args.count >= 1, "Invalid number of argumentss")
        let arguments = ["/bin/bash", "-c", "\(args.map({ $0.shellEscaped() }).joined(separator: " "))"]
        if let output = task(arguments).single() {
            return try output.dematerialize()
        } else {
            throw SystemError(stderror: "Error running command: \(args.joined(separator: " "))", exitcode: 1)
        }
    }

    public func popen(_ args: String..., verbose: Bool = false) throws {
        try popen(args, verbose: verbose)
    }

    public func popen(_ args: [String], verbose _: Bool = false) throws {
        precondition(args.count >= 1, "Invalid number of arguments")
        let arguments = ["/bin/bash", "-c", "\(args.map({ $0.shellEscaped() }).joined(separator: " "))"]
        _ = task(arguments, print: true).wait()
    }

    // MARK: - Fileprivate

    fileprivate func task(_ args: [String], print: Bool = false) -> SignalProducer<SystemResult, SystemError> {
        let task = Task(args.first!, arguments: Array(args.dropFirst()), workingDirectoryPath: nil, environment: nil)
        return task.launch()
            .on(value: {
                if !print { return }
                switch $0 {
                case let .standardError(error):
                    FileHandle.standardError.write(error)
                case let .standardOutput(output):
                    FileHandle.standardOutput.write(output)
                default:
                    break
                }
            })
            .ignoreTaskData()
            .mapError { (error: TaskError) -> SystemError in
                switch error {
                case let TaskError.posixError(code):
                    return SystemError(stderror: nil, exitcode: code)
                case let TaskError.shellTaskFailed(_, code, standardError):
                    return SystemError(stderror: standardError, exitcode: code)
                }
            }
            .map { data in
                let stdout = String(data: data, encoding: .utf8)!
                return SystemResult(stdout: stdout, stderror: "", exitcode: 0)
            }
    }
}
