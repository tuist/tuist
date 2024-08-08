import Foundation
import XCTest

@testable import TuistSupport

open class TuistUnitTestCase: TuistTestCase {
    public var system: MockSystem!
    public var developerEnvironment: MockDeveloperEnvironment!
    public var xcodeController: MockXcodeControlling!
    public var swiftVersionProvider: MockSwiftVersionProviding!

    override open func setUp() {
        super.setUp()
        // System
        system = MockSystem()
        System._shared.mutate { $0 = system }

        swiftVersionProvider = MockSwiftVersionProviding()
        SwiftVersionProvider._shared.mutate { $0 = swiftVersionProvider }

        // Xcode controller
        xcodeController = MockXcodeControlling()
        XcodeController._shared.mutate { $0 = xcodeController }

        // Developer environment
        developerEnvironment = MockDeveloperEnvironment()
        DeveloperEnvironment._shared.mutate { $0 = developerEnvironment }
    }

    override open func tearDown() {
        // System
        system = nil
        System._shared.mutate { $0 = System() }

        swiftVersionProvider = nil
        SwiftVersionProvider._shared.mutate { $0 = SwiftVersionProvider(System.shared) }

        // Xcode controller
        xcodeController = nil
        XcodeController._shared.mutate { $0 = XcodeController() }

        // Environment
        environment = nil
        Environment._shared.mutate { $0 = Environment() }

        // Developer environment
        developerEnvironment = nil
        DeveloperEnvironment._shared.mutate { $0 = DeveloperEnvironment() }

        super.tearDown()
    }
}
