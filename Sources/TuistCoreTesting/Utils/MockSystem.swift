import Foundation
import TuistCore

public final class MockSystem: Systeming {
    private var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]

    public init() {}

    public func stub(args: [String], stderror: String? = nil, stdout: String? = nil, exitstatus: Int? = nil) {
        stubs[args.joined(separator: " ")] = (stderror: stderror, stdout: stdout, exitstatus: exitstatus)
    }

    public func capture2(_ args: [String], verbose _: Bool) -> System2Result {
        let command = args.joined(separator: " ")
        if let stub = stubs[command] {
            return System2Result(stdout: stub.stdout ?? "", exitcode: stub.exitstatus ?? -1)
        } else {
            return System2Result(stdout: "", exitcode: -1)
        }
    }

    public func capture2(_ args: String..., verbose: Bool) -> System2Result {
        return capture2(args, verbose: verbose)
    }

    public func capture2e(_ args: [String], verbose _: Bool) -> System2eResult {
        let command = args.joined(separator: " ")
        if let stub = stubs[command] {
            return System2eResult(std: stub.stdout ?? stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
        } else {
            return System2eResult(std: "", exitcode: -1)
        }
    }

    public func capture2e(_ args: String..., verbose: Bool) -> System2eResult {
        return capture2e(args, verbose: verbose)
    }

    public func capture3(_ args: [String], verbose _: Bool) -> System3Result {
        let command = args.joined(separator: " ")
        if let stub = stubs[command] {
            return System3Result(stdout: stub.stdout ?? "", stderror: stub.stderror ?? "", exitcode: stub.exitstatus ?? -1)
        } else {
            return System3Result(stdout: "", stderror: "", exitcode: -1)
        }
    }

    public func capture3(_ args: String..., verbose: Bool) -> System3Result {
        return capture3(args, verbose: verbose)
    }

    public func popen(_ args: String..., printing: Bool, verbose: Bool, onOutput: ((String) -> Void)?, onError: ((String) -> Void)?, onCompletion: ((Int) -> Void)?) {
        popen(args, printing: printing, verbose: verbose, onOutput: onOutput, onError: onError, onCompletion: onCompletion)
    }

    public func popen(_ args: [String], printing _: Bool, verbose _: Bool, onOutput: ((String) -> Void)?, onError: ((String) -> Void)?, onCompletion: ((Int) -> Void)?) {
        let command = args.joined(separator: " ")
        if let stub = stubs[command] {
            if let stdout = stub.stdout {
                onOutput?(stdout)
            }
            if let stderror = stub.stderror {
                onError?(stderror)
            }
            onCompletion?(stub.exitstatus ?? -1)
        } else {
            onCompletion?(-1)
        }
    }
}
