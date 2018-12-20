import struct Basic.AbsolutePath
import Foundation
import TuistCore

enum MockSystemError: Error, CustomStringConvertible {
    case notStubbedCommand(String)
    case stubbedCommandErrored(String)
    
    var description: String {
        switch self {
        case .notStubbedCommand(let command):
            return "Command '\(command)' not stubbed"
        case .stubbedCommandErrored(let command):
            return "Command '\(command)' errored"
        }
    }
}

public final class MockSystem: Systeming {
    
    private var stubs: [String: (stderror: String?, stdout: String?, exitstatus: Int?)] = [:]
    private var calls: [String] = []
    var swiftVersionStub: (() throws -> String?)?
    var whichStub: ((String) throws -> String?)?

    public init() {}
    
    public func errorCommand(_ arguments: [String], error: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: error, stdout: nil, exitstatus: 1)
    }
    
    public func succeedCommand(_ arguments: [String], output: String? = nil) {
        stubs[arguments.joined(separator: " ")] = (stderror: nil, stdout: output, exitstatus: 0)
    }
    
    public func run(_ arguments: [String]) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = self.stubs[command] else {
            throw MockSystemError.notStubbedCommand(command)
        }
        if stub.exitstatus != 0 {
            throw MockSystemError.stubbedCommandErrored(command)
        }
    }
    
    public func run(_ arguments: String...) throws {
        try self.run(arguments)
    }
    
    public func capture(_ arguments: [String]) throws -> String {
        return try self.capture(arguments, verbose: false, environment: [:])
    }
    
    public func capture(_ arguments: String...) throws -> String {
        return try self.capture(arguments, verbose: false, environment: [:])
    }
    
    public func capture(_ arguments: String..., verbose: Bool, environment: [String : String]) throws -> String {
        return try self.capture(arguments, verbose: verbose, environment: environment)
    }
    
    public func capture(_ arguments: [String], verbose: Bool, environment: [String : String]) throws -> String {
        let command = arguments.joined(separator: " ")
        guard let stub = self.stubs[command] else {
            throw MockSystemError.notStubbedCommand(command)
        }
        if stub.exitstatus != 0 {
            throw MockSystemError.stubbedCommandErrored(command)
        }
        return stub.stdout ?? ""
    }
    
    public func popen(_ arguments: String...) throws {
        try self.popen(arguments)
    }
    
    public func popen(_ arguments: [String]) throws {
        try self.popen(arguments, verbose: false, environment: [:])
    }
    
    public func popen(_ arguments: String..., verbose: Bool, environment: [String : String]) throws {
        try self.popen(arguments, verbose: verbose, environment: environment)
    }
    
    public func popen(_ arguments: [String], verbose: Bool, environment: [String : String]) throws {
        let command = arguments.joined(separator: " ")
        guard let stub = self.stubs[command] else {
            throw MockSystemError.notStubbedCommand(command)
        }
        if stub.exitstatus != 0 {
            throw MockSystemError.stubbedCommandErrored(command)
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
