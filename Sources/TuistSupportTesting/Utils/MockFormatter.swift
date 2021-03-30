import Foundation
import TSCBasic

@testable import TuistSupport

public final class MockFormatter: Formatting {
    public init() {}
    
    var invokedBuildArguments = false
    var invokedBuildArgumentsCount = 0
    var buildArgumentsStub: (() throws  -> [String])?
    
    public func buildArguments() throws -> [String] {
        invokedBuildArguments = true
        invokedBuildArgumentsCount += 1
        return (try buildArgumentsStub?()) ?? []
    }
}
