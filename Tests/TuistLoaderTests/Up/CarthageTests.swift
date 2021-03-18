import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CarthageTests: TuistUnitTestCase {
    var subject: Carthage!

    override func setUp() {
        super.setUp()
        subject = Carthage()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_bootstrap_regularFrameworks() throws {
        let temporaryPath = try self.temporaryPath()
        system.whichStub = { tool in
            if tool == "carthage" {
                return "/path/to/carthage"
            } else {
                throw NSError.test()
            }
        }
        system.succeedCommand(
            "/path/to/carthage",
            "bootstrap",
            "--project-directory",
            temporaryPath.pathString,
            "--platform",
            "iOS,macOS",
            "Alamofire",
            output: ""
        )

        try subject.bootstrap(
            path: temporaryPath,
            platforms: [.iOS, .macOS],
            useXCFrameworks: false,
            noUseBinaries: false,
            dependencies: ["Alamofire"]
        )
    }

    func test_bootstrap_XCFrameworks() throws {
        let temporaryPath = try self.temporaryPath()
        system.whichStub = { tool in
            if tool == "carthage" {
                return "/path/to/carthage"
            } else {
                throw NSError.test()
            }
        }
        system.succeedCommand(
            "/path/to/carthage",
            "bootstrap",
            "--project-directory",
            temporaryPath.pathString,
            "--use-xcframeworks",
            "--platform",
            "iOS,macOS",
            "Alamofire",
            output: ""
        )

        try subject.bootstrap(
            path: temporaryPath,
            platforms: [.iOS, .macOS],
            useXCFrameworks: true,
            noUseBinaries: false,
            dependencies: ["Alamofire"]
        )
    }

    func test_bootstrap_XCFrameworks_and_noUseBinaries() throws {
        let temporaryPath = try self.temporaryPath()
        system.whichStub = { tool in
            if tool == "carthage" {
                return "/path/to/carthage"
            } else {
                throw NSError.test()
            }
        }
        system.succeedCommand(
            "/path/to/carthage",
            "bootstrap",
            "--project-directory",
            temporaryPath.pathString,
            "--use-xcframeworks",
            "--no-use-binaries",
            "--platform",
            "iOS,macOS",
            "Alamofire",
            output: ""
        )

        try subject.bootstrap(
            path: temporaryPath,
            platforms: [.iOS, .macOS],
            useXCFrameworks: true,
            noUseBinaries: true,
            dependencies: ["Alamofire"]
        )
    }

    func test_outdated() throws {
        let jsonEncoder = JSONEncoder()
        let temporaryPath = try self.temporaryPath()

        let cartfileResolved = """
        github "Tuist/DependencyA" "4.8.0"
        github "Tuist/DependencyB" "4.9.0"
        github "Tuist/DependencyC" "4.10.0"
        binary "Tuist/DependencyD" "4.11.0"
        binary "Tuist/DependencyE.json" "4.12.0"
        """
        let cartfileResolvedPath = temporaryPath.appending(component: "Cartfile.resolved")
        try cartfileResolved.write(
            to: cartfileResolvedPath.url,
            atomically: true,
            encoding: .utf8
        )

        let carthagePath = temporaryPath.appending(component: "Carthage")
        try FileHandler.shared.createFolder(carthagePath)
        let buildPath = carthagePath.appending(component: "Build")
        try FileHandler.shared.createFolder(buildPath)

        // Dependency A: Outdated
        // Dependency B: Up to date
        // Dependency C: Missing version file
        // Dependency D: Binary without extension, missing version file
        // Dependency E: Binary with extension, missing version file
        let dependencyAVersionData = try jsonEncoder.encode(CarthageVersionFile(commitish: "4.7.0"))
        try dependencyAVersionData.write(to: buildPath.appending(component: ".DependencyA.version").url)

        let dependencyBVersionData = try jsonEncoder.encode(CarthageVersionFile(commitish: "4.9.0"))
        try dependencyBVersionData.write(to: buildPath.appending(component: ".DependencyB.version").url)

        let got = try subject.outdated(path: temporaryPath)

        XCTAssertEqual(got, ["DependencyA", "DependencyC", "DependencyD", "DependencyE"])
    }
}
