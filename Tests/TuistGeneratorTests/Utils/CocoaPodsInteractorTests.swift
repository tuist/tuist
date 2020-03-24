import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class CocoaPodsInteractorErrorTests: XCTestCase {
    func test_type() {
        XCTAssertEqual(CocoaPodsInteractorError.cocoapodsNotFound.type, .abort)
        XCTAssertEqual(CocoaPodsInteractorError.outdatedRepository.type, .abort)
    }

    func test_description() {
        XCTAssertEqual(CocoaPodsInteractorError.cocoapodsNotFound.description, "CocoaPods was not found either in Bundler nor in the environment")
        XCTAssertEqual(CocoaPodsInteractorError.outdatedRepository.description, "The installation of CocoaPods dependencies might have failed because the CocoaPods repository is outdated")
    }
}

final class CocoaPodsInteractorTests: TuistUnitTestCase {
    var subject: CocoaPodsInteractor!

    override func setUp() {
        super.setUp()
        subject = CocoaPodsInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install_when_cocoapods_cannot_be_found() {
        // Given
        system.errorCommand(["bundle", "show", "cocoapods"])
        system.whichStub = { _ in
            throw NSError.test()
        }
        let cocoapods = CocoaPodsNode.test()
        let graph = Graph.test(cocoapods: [cocoapods.path: cocoapods])

        // Then
        XCTAssertThrowsSpecific(try subject.install(graph: graph),
                                CocoaPodsInteractorError.cocoapodsNotFound)
    }

    func test_install_when_theCocoaPodsFromBundlerCanBeUsed() throws {
        // Given
        let cocoapods = CocoaPodsNode.test()
        let graph = Graph.test(cocoapods: [cocoapods.path: cocoapods])

        system.succeedCommand(["bundle", "show", "cocoapods"])
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=\(cocoapods.path.pathString)"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)")
    }

    func test_install_when_theCocoaPodsFromTheSystemCanBeUsed() throws {
        // Given
        let cocoapods = CocoaPodsNode.test()
        let graph = Graph.test(cocoapods: [cocoapods.path: cocoapods])

        system.errorCommand(["bundle", "show", "cocoapods"])
        system.whichStub = {
            if $0 == "pod" { return "/path/to/pod" }
            else { throw NSError.test() }
        }
        system.succeedCommand(["pod", "install", "--project-directory=\(cocoapods.path.pathString)"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)")
    }

    func test_install_when_theCocoaPodsSpecsRepoIsOutdated() throws {
        // Given
        let cocoapods = CocoaPodsNode.test()
        let graph = Graph.test(cocoapods: [cocoapods.path: cocoapods])

        system.succeedCommand(["bundle", "show", "cocoapods"])
        system.errorCommand(["bundle", "exec", "pod", "install", "--project-directory=\(cocoapods.path.pathString)"], error: "[!] CocoaPods could not find compatible versions for pod")
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=\(cocoapods.path.pathString)", "--repo-update"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("The local CocoaPods specs repository is outdated. Re-running 'pod install' updating the repository.")
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)")
    }
}
