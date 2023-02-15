import Combine
import Foundation
import TSCBasic
import XCTest
@testable import TuistSupport

public final class MockSystem: Systeming {
    public var env: [String: String] = [:]

    // swiftlint:disable:next large_tuple
    public var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var calls: [String] = []
    public var whichStub: ((String) throws -> String?)?
    public var swiftVersionStub: (() throws -> String)?
    public var swiftlangVersionStub: (() throws -> String)?

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

    public func runAndCollectOutput(_ arguments: [String]) async throws -> SystemCollectedOutput {
        var values = publisher(arguments)
            .mapToString()
            .collectOutput()
            .eraseToAnyPublisher()
            .stream
            .makeAsyncIterator()

        return try await values.next()!
    }

    public func publisher(_ arguments: [String]) -> AnyPublisher<SystemEvent<Data>, Error> {
        publisher(arguments, verbose: false, environment: env)
    }

    public func publisher(
        _ arguments: [String],
        verbose _: Bool,
        environment _: [String: String]
    ) -> AnyPublisher<SystemEvent<Data>, Error> {
        AnyPublisher<SystemEvent<Data>, Error>.create { subscriber in
            let command = arguments.joined(separator: " ")
            guard let stub = self.stubs[command] else {
                subscriber
                    .send(completion: .failure(
                        TuistSupport.SystemError
                            .terminated(command: arguments.first!, code: 1, standardError: Data())
                    ))
                return AnyCancellable {}
            }
            guard stub.exitstatus == 0 else {
                if let error = stub.stderror {
                    subscriber.send(.standardError(error.data(using: .utf8)!))
                }
                subscriber
                    .send(completion: .failure(
                        TuistSupport.SystemError
                            .terminated(command: arguments.first!, code: 1, standardError: Data())
                    ))

                return AnyCancellable {}
            }
            if let stdout = stub.stdout {
                subscriber.send(.standardOutput(stdout.data(using: .utf8)!))
            }
            subscriber.send(completion: .finished)
            return AnyCancellable {}
        }
    }

    public func publisher(_ arguments: [String], pipeTo _: [String]) -> AnyPublisher<SystemEvent<Data>, Error> {
        AnyPublisher<SystemEvent<Data>, Error>.create { subscriber in
            let command = arguments.joined(separator: " ")
            guard let stub = self.stubs[command] else {
                subscriber
                    .send(completion: .failure(
                        TuistSupport.SystemError
                            .terminated(command: arguments.first!, code: 1, standardError: Data())
                    ))
                return AnyCancellable {}
            }
            guard stub.exitstatus == 0 else {
                if let error = stub.stderror {
                    subscriber.send(.standardError(error.data(using: .utf8)!))
                }
                subscriber
                    .send(completion: .failure(
                        TuistSupport.SystemError
                            .terminated(command: arguments.first!, code: 1, standardError: Data())
                    ))

                return AnyCancellable {}
            }
            if let stdout = stub.stdout {
                subscriber.send(.standardOutput(stdout.data(using: .utf8)!))
            }
            subscriber.send(completion: .finished)
            return AnyCancellable {}
        }
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

    public func swiftVersion() throws -> String {
        if let swiftVersionStub = swiftVersionStub {
            return try swiftVersionStub()
        } else {
            throw TestError("Call to non-stubbed method swiftVersion")
        }
    }

    public func swiftlangVersion() throws -> String {
        if let swiftlangVersion = swiftlangVersionStub {
            return try swiftlangVersion()
        } else {
            throw TestError("Call to non-stubbed method swiftlangVersion")
        }
    }

    public func which(_ name: String) throws -> String {
        if let path = try whichStub?(name) {
            return path
        } else {
            throw TestError("Call to non-stubbed method which")
        }
    }

    public var chmodStub: ((FileMode, AbsolutePath, Set<FileMode.Option>) throws -> Void)?
    public func chmod(
        _ mode: FileMode,
        path: AbsolutePath,
        options: Set<FileMode.Option>
    ) throws {
        try chmodStub?(mode, path, options)
    }
}
