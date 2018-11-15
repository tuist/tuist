import struct Basic.AbsolutePath
import Foundation
import ReactiveSwift
import Result
import TuistCore

public final class MockSystem: Systeming {
    private var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int32?)] = [:]
    private var calls: [String] = []
    var swiftVersionStub: (() throws -> String?)?
    var whichStub: ((String) throws -> String?)?

    public init() {}

    public func stub(args: [String], stderror: String? = nil, stdout: String? = nil, exitstatus: Int32? = nil) {
        stubs[args.joined(separator: " ")] = (stderror: stderror, stdout: stdout, exitstatus: exitstatus)
    }

    public func capture(_ launchPath: String, arguments: String..., verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws -> SystemResult {
        return try capture(launchPath, arguments: arguments, verbose: verbose, workingDirectoryPath: workingDirectoryPath, environment: environment)
    }

    public func capture(_ launchPath: String, arguments: [String], verbose _: Bool, workingDirectoryPath: AbsolutePath?, environment _: [String: String]?) throws -> SystemResult {
        var arguments = arguments
        arguments.insert(launchPath, at: 0)
        let command = arguments.joined(separator: " ")
        calls.append(command)
        if let stub = stubs[command] {
            return SystemResult(stdout: stub.stdout ?? "", stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
        } else {
            return SystemResult(stdout: "", stderror: "", exitcode: -1)
        }
    }

    public func popen(_ launchPath: String, arguments: String..., verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws {
        try popen(launchPath, arguments: arguments, verbose: verbose, workingDirectoryPath: workingDirectoryPath, environment: environment)
    }

    public func popen(_ launchPath: String, arguments: [String], verbose _: Bool, workingDirectoryPath: AbsolutePath?, environment _: [String: String]?) throws {
        var arguments = arguments
        arguments.insert(launchPath, at: 0)
        let command = arguments.joined(separator: " ")
        calls.append(command)
        if let stub = stubs[command] {
            if stub.exitstatus != 0 {
                throw SystemError(stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
            }
        } else {
            throw SystemError(stderror: "Command not supported: \(command)", exitcode: -1)
        }
    }

    public func task(_ launchPath: String, arguments: [String], print _: Bool, workingDirectoryPath: AbsolutePath?, environment _: [String: String]?) -> SignalProducer<SystemResult, SystemError> {
        var arguments = arguments
        arguments.insert(launchPath, at: 0)
        let command = arguments.joined(separator: " ")
        calls.append(command)
        return SignalProducer { () -> Result<SystemResult, SystemError> in
            if let stub = self.stubs[command] {
                if stub.exitstatus != 0 {
                    return Result.failure(SystemError(stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1))
                } else {
                    return Result.success(SystemResult(stdout: stub.stdout ?? "", stderror: "", exitcode: 0))
                }
            } else {
                return Result.failure(SystemError(stderror: "Command not supported: \(command)", exitcode: -1))
            }
        }
    }

    public func swiftVersion() throws -> String? {
        return try swiftVersionStub?()
    }

    public func which(_ name: String) throws -> String {
        if let path = try whichStub?(name) {
            return path
        } else {
            throw NSError.test()
        }
    }

    public func called(_ args: String...) -> Bool {
        let command = args.joined(separator: " ")
        return calls.contains(command)
    }
}
