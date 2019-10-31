import Foundation
import XCTest

@testable import TuistSupport

public class TuistUnitTestCase: TuistTestCase {
    public var system: MockSystem!
    public var environment: MockEnvironment!
    public var xcodeController: MockXcodeController!

    public override func setUp() {
        super.setUp()
        // System
        system = MockSystem()
        System.shared = system

        // Xcode controller
        xcodeController = MockXcodeController()
        XcodeController.shared = xcodeController

        // Environment
        // swiftlint:disable force_try
        environment = try! MockEnvironment()
        Environment.shared = environment
    }

    public override func tearDown() {
        // System
        system = nil
        System.shared = System()

        // Printer
        printer = nil
        Printer.shared = Printer()

        // Xcode controller
        xcodeController = nil
        XcodeController.shared = XcodeController()

        // Environment
        environment = nil
        Environment.shared = Environment()

        super.tearDown()
    }
}
