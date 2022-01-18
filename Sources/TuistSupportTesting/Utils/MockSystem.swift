import Foundation
import RxSwift
import TSCBasic
import TuistSupport
import XCTest

public final class MockSystem: Systeming {
    public var env: [String: String] = ProcessInfo.processInfo.environment
    // swiftlint:disable:next large_tuple
    public var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var calls: [String] = []
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
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            let standardError = (stub.stderror?.data(using: .utf8)) ?? Data()
            throw TuistSupport.SystemError.terminated(
                command: arguments.first!,
                code: Int32(stub.exitstatus ?? 1),
                standardError: standardError
            )
        }
        calls.append(arguments.joined(separator: " "))
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
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        calls.append(arguments.joined(separator: " "))
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
        redirection: TSCBasic.Process.OutputRedirection
    ) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = stubs[command] else {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            if let error = stub.stderror {
                redirection.outputClosures?.stderrClosure([UInt8](error.data(using: .utf8)!))
            }
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        calls.append(arguments.joined(separator: " "))
    }

    public func runAndCollectOutput(_ arguments: [String]) async throws -> SystemCollectedOutput {
        try await observable(arguments, verbose: false)
            .mapToString()
            .collectOutput()
            .asSingle()
            .value
    }

    public func observable(_ arguments: [String]) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: false)
    }

    public func observable(_ arguments: [String], verbose: Bool) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: verbose, environment: [:])
    }

    public func observable(_ arguments: [String], verbose _: Bool,
                           environment _: [String: String]) -> Observable<SystemEvent<Data>>
    {
        Observable.create { observer -> Disposable in
            let command = arguments.joined(separator: " ")
            guard let stub = self.stubs[command] else {
                observer.onError(TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data()))
                return Disposables.create()
            }
            guard stub.exitstatus == 0 else {
                if let error = stub.stderror {
                    observer.onNext(.standardError(error.data(using: .utf8)!))
                }
                observer.onError(TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data()))
                return Disposables.create()
            }
            if let stdout = stub.stdout {
                observer.onNext(.standardOutput(stdout.data(using: .utf8)!))
            }
            observer.onCompleted()
            return Disposables.create()
        }
    }

    public func observable(_ arguments: [String], pipedToArguments: [String]) -> Observable<SystemEvent<Data>> {
        observable(arguments, environment: [:], pipeTo: pipedToArguments)
    }

    public func observable(_ arguments: [String], environment _: [String: String],
                           pipeTo _: [String]) -> Observable<SystemEvent<Data>>
    {
        Observable.create { observer -> Disposable in
            let command = arguments.joined(separator: " ")
            guard let stub = self.stubs[command] else {
                observer.onError(TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data()))
                return Disposables.create()
            }
            guard stub.exitstatus == 0 else {
                if let error = stub.stderror {
                    observer.onNext(.standardError(error.data(using: .utf8)!))
                }
                observer.onError(TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data()))
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
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
        if stub.exitstatus != 0 {
            throw TuistSupport.SystemError.terminated(command: arguments.first!, code: 1, standardError: Data())
        }
    }

    var swiftVersionStub: (() throws -> String)?
    public func swiftVersion() throws -> String {
        if let swiftVersionStub = swiftVersionStub {
            return try swiftVersionStub()
        } else {
            throw TestError("Call to non-stubbed method swiftVersion")
        }
    }

    public func which(_ name: String) throws -> String {
        if let path = try whichStub?(name) {
            return path
        } else {
            throw NSError.test()
        }
    }

    public func called(_ args: [String]) -> Bool {
        let command = args.joined(separator: " ")
        return calls.contains(command)
    }

    public func called(_ args: String...) -> Bool {
        called(args)
    }
}
