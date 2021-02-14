import Foundation
import TSCUtility
@testable import TuistSupport

public final class MockCarthageController: CarthageControlling {
    public init() { }
    
    var invokedCanUseSystemCarthage = false
    var invokedCanUseSystemCarthageCount = 0
    var canUseSystemCarthageStub: (() -> Bool)?
    
    public func canUseSystemCarthage() -> Bool {
        invokedCanUseSystemCarthage = true
        invokedCanUseSystemCarthageCount += 1
        if let stub = canUseSystemCarthageStub {
            return stub()
        } else {
            return false
        }
    }
    
    var invokedCarthageVersion = false
    var invokedCarthageVersionCount = 0
    var carthageVersionStub: (() throws -> Version)?
    
    public func carthageVersion() throws -> Version {
        invokedCarthageVersion = true
        invokedCarthageVersionCount += 1
        if let stub = carthageVersionStub {
            return try stub()
        } else {
            return Version(0, 0, 0)
        }
    }
    
    var invokedIsXCFrameworksProductionSupported = false
    var invokedIsXCFrameworksProductionSupportedCount = 0
    var isXCFrameworksProductionSupportedStub: (() -> Bool)?
    
    public func isXCFrameworksProductionSupported() throws -> Bool {
        invokedIsXCFrameworksProductionSupported = true
        invokedIsXCFrameworksProductionSupportedCount += 1
        if let stub = isXCFrameworksProductionSupportedStub {
            return stub()
        } else {
            return false
        }
    }
}
