import Foundation
import XCTest

@testable import TuistSupport

open class TuistUnitTestCase: TuistTestCase {
    public var system: MockSystem!
    public var developerEnvironment: MockDeveloperEnvironment!
    public var xcodeController: MockXcodeController!

    open override func setUpWithError() throws {
        try super.setUpWithError()
        
        // System
        system = MockSystem()
        System.shared = system

        // Xcode controller
        xcodeController = MockXcodeController()
        XcodeController.shared = xcodeController

        // Developer environment
        developerEnvironment = MockDeveloperEnvironment()
        DeveloperEnvironment.shared = developerEnvironment
    }

    override open func tearDown() {
        // System
        system = nil
        System.shared = System()

        // Xcode controller
        xcodeController = nil
        XcodeController.shared = XcodeController()

        // Developer environment
        developerEnvironment = nil
        DeveloperEnvironment.shared = DeveloperEnvironment()

        super.tearDown()
    }
}
