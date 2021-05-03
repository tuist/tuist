import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageControllerTests: TuistUnitTestCase {
    private var subject: CarthageController!

    override func setUp() {
        super.setUp()

        subject = CarthageController()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_canUseSystemCarthage_available() {
        // Given
        system.whichStub = { _ in "path" }

        // When / Then
        XCTAssertTrue(subject.canUseSystemCarthage())
    }

    func test_canUseSystemCarthage_unavailable() {
        // Given
        system.whichStub = { _ in throw NSError.test() }

        // When / Then
        XCTAssertFalse(subject.canUseSystemCarthage())
    }

    func test_carthageVersion_carthageNotFound() {
        // Given
        system.errorCommand("/usr/bin/env", "carthage", "version")

        // When / Then
        XCTAssertThrowsSpecific(try subject.carthageVersion(), CarthageControllerError.carthageNotFound)
    }

    func test_carthageVersion_success() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.37.0", exitstatus: 0)

        // When / Then
        XCTAssertEqual(try subject.carthageVersion(), Version(0, 37, 0))
    }

    func test_isXCFrameworksProductionSupported_notSupported() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.36.1", exitstatus: 0)

        // When / Then
        XCTAssertFalse(try subject.isXCFrameworksProductionSupported())
    }

    func test_isXCFrameworksProductionSupported_supported() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.37.0", exitstatus: 0)

        // When / Then
        XCTAssertTrue(try subject.isXCFrameworksProductionSupported())
    }

    func test_bootstrap() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: [], options: []))
    }

    func test_bootstrap_with_platforms() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: [.iOS], options: []))
    }

    func test_bootstrap_with_platforms_and_options() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--no-use-binaries",
            "--use-xcframeworks",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: [.iOS], options: [.noUseBinaries, .useXCFrameworks]))
    }

    func test_update() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: [], options: []))
    }

    func test_update_with_platforms() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: [.iOS], options: []))
    }

    func test_update_with_platforms_and_options() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--no-use-binaries",
            "--use-xcframeworks",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: [.iOS], options: [.noUseBinaries, .useXCFrameworks]))
    }
}
