import Foundation
import Path
import TSCBasic
import XCTest
@testable import TuistSupport

public final class MockSystem: Systeming {
    public var env: [String: String] = [:]

    // swiftlint:disable:next large_tuple
    public var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var calls: [String] = []
    public var whichStub: ((String) throws -> String?)?

    public init() {}

    public func succeedCommand(_ arguments: [String], output: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: nil, stdout: output, exitstatus: 0)
    }

    public func errorCommand(_ arguments: [String], error: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: error, stdout: nil, exitstatus: 1)
    }

    public func called(_ args: [String]) -> Bool {
        let command = args.joined(separator: " ")
        return calls.contains(command)
    }

    public func run(_ arguments: [String]) throws {
        _ = try capture(arguments)
    }

    public func capture(_ arguments: [String]) throws -> String {
        try capture(arguments, verbose: false, environment: env)
    }

    public func capture(_ arguments: [String], verbose _: Bool, environment _: [String: String]) throws -> String {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(
                command: arguments.first!,
                code: 1,
                standardError: Data((stub.stderror ?? "").utf8)
            )
        }
        calls.append(arguments.joined(separator: " "))
        return stub.stdout ?? ""
    }

    public func runAndPrint(_ arguments: [String]) throws {
        _ = try capture(arguments, verbose: false, environment: env)
    }

    public func runAndPrint(_ arguments: [String], verbose _: Bool, environment _: [String: String]) throws {
        _ = try capture(arguments, verbose: false, environment: env)
    }

    public func run(
        _ arguments: [String],
        verbose _: Bool,
        environment _: [String: String],
        redirection _: TSCBasic.Process.OutputRedirection
    ) throws {
        _ = try capture(arguments, verbose: false, environment: env)
    }

    public func runAndCollectOutput(_ arguments: [String]) async throws -> SystemCollectedOutput {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError
                .terminated(command: arguments.first!, code: 1, standardError: Data())
        }

        guard stub.exitstatus == 0 else {
            throw TuistSupport.SystemError
                .terminated(command: arguments.first!, code: 1, standardError: stub.stderror?.data(using: .utf8) ?? Data())
        }

        return SystemCollectedOutput(
            standardOutput: stub.stdout ?? "",
            standardError: stub.stderror ?? ""
        )
    }

    public func async(_ arguments: [String]) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
    }

    public func which(_ name: String) throws -> String {
        if let path = try whichStub?(name) {
            return path
        } else {
            throw TestError("Call to non-stubbed method which")
        }
    }

    public var chmodStub: ((FileMode, Path.AbsolutePath, Set<FileMode.Option>) throws -> Void)?
    public func chmod(
        _ mode: FileMode,
        path: Path.AbsolutePath,
        options: Set<FileMode.Option>
    ) throws {
        try chmodStub?(mode, path, options)
    }
}
