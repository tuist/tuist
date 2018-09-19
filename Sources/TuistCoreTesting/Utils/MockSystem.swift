import Foundation
import TuistCore

public final class MockSystem: Systeming {
    private var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int32?)] = [:]
    private var calls: [String] = []
    var swiftVersionStub: (() throws -> String?)?

    public init() {}

    public func stub(args: [String], stderror: String? = nil, stdout: String? = nil, exitstatus: Int32? = nil) {
        stubs[args.joined(separator: " ")] = (stderror: stderror, stdout: stdout, exitstatus: exitstatus)
    }

    public func capture(_ args: String..., verbose: Bool) throws -> SystemResult {
        return try capture(args, verbose: verbose)
    }

    public func capture(_ args: [String], verbose _: Bool) throws -> SystemResult {
        let command = args.joined(separator: " ")
        calls.append(command)
        if let stub = stubs[command] {
            return SystemResult(stdout: stub.stdout ?? "", stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
        } else {
            return SystemResult(stdout: "", stderror: "", exitcode: -1)
        }
    }

    public func popen(_ args: String..., verbose: Bool) throws {
        try popen(args, verbose: verbose)
    }

    public func popen(_ args: [String], verbose _: Bool) throws {
        let command = args.joined(separator: " ")
        calls.append(command)
        if let stub = stubs[command] {
            if stub.exitstatus != 0 {
                throw SystemError(stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
            }
        } else {
            throw SystemError(stderror: "Command not supported: \(command)", exitcode: -1)
        }
    }

    public func swiftVersion() throws -> String? {
        return try swiftVersionStub?()
    }

    public func called(_ args: String...) -> Bool {
        let command = args.joined(separator: " ")
        return calls.contains(command)
    }
}
