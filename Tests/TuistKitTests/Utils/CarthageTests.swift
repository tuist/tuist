import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class CarthageTests: XCTestCase {
    var subject: Carthage!
    var system: MockSystem!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        fileHandler = try! MockFileHandler()
        subject = Carthage(system: system)
    }

    func test_update() throws {
        system.whichStub = { tool in
            if tool == "carthage" {
                return "/path/to/carthage"
            } else {
                throw NSError.test()
            }
        }
        system.succeedCommand("/path/to/carthage", "update", "--project-directory", fileHandler.currentPath.pathString, "--platform", "iOS,macOS", "Alamofire",
                              output: "")

        try subject.update(path: fileHandler.currentPath,
                           platforms: [.iOS, .macOS],
                           dependencies: ["Alamofire"])
    }

    func test_outdated() throws {
        let jsonEncoder = JSONEncoder()

        let cartfileResolved = """
        github "Tuist/DependencyA" "4.8.0"
        github "Tuist/DependencyB" "4.9.0"
        github "Tuist/DependencyC" "4.10.0"
        """
        let cartfileResolvedPath = fileHandler.currentPath.appending(component: "Cartfile.resolved")
        try cartfileResolved.write(to: cartfileResolvedPath.url,
                                   atomically: true,
                                   encoding: .utf8)

        let carthagePath = fileHandler.currentPath.appending(component: "Carthage")
        try fileHandler.createFolder(carthagePath)
        let buildPath = carthagePath.appending(component: "Build")
        try fileHandler.createFolder(buildPath)

        // Dependency A: Outdated
        // Dependency B: Up to date
        // Dependency C: Missing version file
        let dependencyAVersionData = try jsonEncoder.encode(CarthageVersionFile(commitish: "4.7.0"))
        try dependencyAVersionData.write(to: buildPath.appending(component: ".DependencyA.version").url)

        let dependencyBVersionData = try jsonEncoder.encode(CarthageVersionFile(commitish: "4.9.0"))
        try dependencyBVersionData.write(to: buildPath.appending(component: ".DependencyB.version").url)

        let got = try subject.outdated(path: fileHandler.currentPath)

        XCTAssertEqual(got, ["DependencyA", "DependencyC"])
    }
}
