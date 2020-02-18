import Basic
import Foundation
import RxSwift
import TuistSupport
import XCTest

public final class MockSystem: Systeming {
    public var env: [String: String] = ProcessInfo.processInfo.environment
    // swiftlint:disable:next large_tuple
    private var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var calls: [String] = []
    var swiftVersionStub: (() throws -> String?)?
    var whichStub: ((String) throws -> String?)?

    public init() {}

    public func errorCommand(_ arguments: String..., error: String? = nil) {
        errorCommand(arguments, error: error)
    }

    public func errorCommand(_ arguments: [String], error: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: error, stdout: nil, exitstatus: 1)
    }

    public func succeedCommand(_ arguments: String..., output: String? = nil) {
        succeedCommand(arguments, output: output)
    }

    public func succeedCommand(_ arguments: [String], output: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: nil, stdout: output, exitstatus: 0)
    }

    public func run(_ arguments: [String]) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(code: 1, error: "command '\(command)' not stubbed")
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(code: 1, error: stub.stderror ?? "")
        }
    }

    public func run(_ arguments: String...) throws {
        try run(arguments)
    }

    public func capture(_ arguments: [String]) throws -> String {
        try capture(arguments, verbose: false, environment: [:])
    }

    public func capture(_ arguments: String...) throws -> String {
        try capture(arguments, verbose: false, environment: [:])
    }

    public func capture(_ arguments: String..., verbose: Bool, environment: [String: String]) throws -> String {
        try capture(arguments, verbose: verbose, environment: environment)
    }

    public func capture(_ arguments: [String], verbose _: Bool, environment _: [String: String]) throws -> String {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(code: 1, error: "command '\(command)' not stubbed")
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(code: 1, error: stub.stderror ?? "")
        }
        return stub.stdout ?? ""
    }

    public func runAndPrint(_ arguments: String...) throws {
        try runAndPrint(arguments)
    }

    public func runAndPrint(_ arguments: [String]) throws {
        try runAndPrint(arguments, verbose: false, environment: [:])
    }

    public func runAndPrint(_ arguments: String..., verbose: Bool, environment: [String: String]) throws {
        try runAndPrint(arguments, verbose: verbose, environment: environment)
    }

    public func runAndPrint(_ arguments: [String], verbose: Bool, environment: [String: String]) throws {
        try runAndPrint(arguments, verbose: verbose, environment: environment, redirection: .none)
    }

    public func runAndPrint(
        _ arguments: [String],
        verbose _: Bool,
        environment _: [String: String],
        redirection: Basic.Process.OutputRedirection
    ) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(code: 1, error: "command '\(command)' not stubbed")
        }
        if stub.exitstatus != 0 {
            if let error = stub.stderror {
                redirection.outputClosures?.stderrClosure([UInt8](error.data(using: .utf8)!))
            }
            throw TuistSupport.SystemError.terminated(code: 1, error: stub.stderror ?? "")
        }
    }

    public func observable(_ arguments: [String]) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: false)
    }

    public func observable(_ arguments: [String], verbose: Bool) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: verbose, environment: [:])
    }

    public func observable(_ arguments: [String], verbose _: Bool, environment _: [String: String]) -> Observable<SystemEvent<Data>> {
        Observable.create { (observer) -> Disposable in
            let command = arguments.joined(separator: " ")
            guard let stub = self.stubs[command] else {
                observer.onError(TuistSupport.SystemError.terminated(code: 1, error: "command '\(command)' not stubbed"))
                return Disposables.create()
            }
            guard stub.exitstatus == 0 else {
                if let error = stub.stderror {
                    observer.onNext(.standardError(error.data(using: .utf8)!))
                }
                observer.onError(TuistSupport.SystemError.terminated(code: 1, error: stub.stderror ?? ""))
                return Disposables.create()
            }
            if let stdout = stub.stdout {
                observer.onNext(.standardOutput(stdout.data(using: .utf8)!))
            }
            observer.onCompleted()
            return Disposables.create()
        }
    }

    public func async(_ arguments: [String]) throws {
        try async(arguments, verbose: false, environment: [:])
    }

    public func async(_ arguments: [String], verbose _: Bool, environment _: [String: String]) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(code: 1, error: "command '\(command)' not stubbed")
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(code: 1, error: stub.stderror ?? "")
        }
    }

    public func swiftVersion() throws -> String? {
        try swiftVersionStub?()
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
