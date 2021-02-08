import Foundation
import TuistCore
import TuistCoreTesting
import TuistGraph
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
        let graph = ValueGraph.test(dependencies: [ValueGraphDependency.cocoapods(path: "/"): Set()])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // Then
        XCTAssertThrowsSpecific(try subject.install(graphTraverser: graphTraverser),
                                CocoaPodsInteractorError.cocoapodsNotFound)
    }

    func test_install_when_theCocoaPodsFromBundlerCanBeUsed() throws {
        // Given
        let graph = ValueGraph.test(dependencies: [ValueGraphDependency.cocoapods(path: "/"): Set()])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        system.succeedCommand(["bundle", "show", "cocoapods"])
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=/"])

        // When
        try subject.install(graphTraverser: graphTraverser)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in /")
    }

    func test_install_when_theCocoaPodsFromTheSystemCanBeUsed() throws {
        // Given
        let graph = ValueGraph.test(dependencies: [ValueGraphDependency.cocoapods(path: "/"): Set()])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        system.errorCommand(["bundle", "show", "cocoapods"])
        system.whichStub = {
            if $0 == "pod" { return "/path/to/pod" }
            else { throw NSError.test() }
        }
        system.succeedCommand(["pod", "install", "--project-directory=/"])

        // When
        try subject.install(graphTraverser: graphTraverser)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in /")
    }

    func test_install_when_theCocoaPodsSpecsRepoIsOutdated() throws {
        // Given
        let graph = ValueGraph.test(dependencies: [ValueGraphDependency.cocoapods(path: "/"): Set()])
        let graphTraverser = ValueGraphTraverser(graph: graph)

        system.succeedCommand(["bundle", "show", "cocoapods"])
        system.errorCommand(["bundle", "exec", "pod", "install", "--project-directory=/"], error: "[!] CocoaPods could not find compatible versions for pod")
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=/", "--repo-update"])

        // When
        try subject.install(graphTraverser: graphTraverser)

        // Then
        XCTAssertPrinterOutputContains("The local CocoaPods specs repository is outdated. Re-running 'pod install' updating the repository.")
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in /")
    }
}
