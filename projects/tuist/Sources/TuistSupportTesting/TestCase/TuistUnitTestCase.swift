import Foundation
import XCTest

@testable import TuistSupport

open class TuistUnitTestCase: TuistTestCase {
    public var system: MockSystem!
    public var xcodeController: MockXcodeController!

    override open func setUp() {
        super.setUp()
        // System
        system = MockSystem()
        System.shared = system

        // Xcode controller
        xcodeController = MockXcodeController()
        XcodeController.shared = xcodeController
    }

    override open func tearDown() {
        // System
        system = nil
        System.shared = System()

        // Xcode controller
        xcodeController = nil
        XcodeController.shared = XcodeController()

        // Environment
        environment = nil
        Environment.shared = Environment()

        super.tearDown()
    }
}
