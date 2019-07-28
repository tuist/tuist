import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class CocoaPodsInteractorErrorTests: XCTestCase {
    func test_type() {
        XCTAssertEqual(CocoaPodsInteractorError.cocoapodsNotFound.type, .abort)
    }

    func test_description() {
        XCTAssertEqual(CocoaPodsInteractorError.cocoapodsNotFound.description, "CocoaPods was not found either in Bundler nor in the environment")
    }
}

final class CocoaPodsInteractorTests: XCTestCase {
    var printer: MockPrinter!
    var system: MockSystem!
    var subject: CocoaPodsInteractor!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        system = MockSystem()
        subject = CocoaPodsInteractor(printer: printer, system: system)
    }

    func test_install_when_cocoapods_cannot_be_found() {
        // Given
        system.errorCommand(["bundle", "show", "cocoapods"])
        system.whichStub = { _ in
            throw NSError.test()
        }
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let cocoapods = CocoaPodsNode.test()
        cache.add(cocoapods: cocoapods)

        // Then
        XCTAssertThrowsError(try subject.install(graph: graph)) {
            XCTAssertEqual($0 as? CocoaPodsInteractorError, CocoaPodsInteractorError.cocoapodsNotFound)
        }
    }

    func test_install_when_theCocoaPodsFromBundlerCanBeUsed() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let cocoapods = CocoaPodsNode.test()
        cache.add(cocoapods: cocoapods)

        system.succeedCommand(["bundle", "show", "cocoapods"])
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=\(cocoapods.path.pathString)", "--repo-update"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertTrue(printer.printSectionArgs.contains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)"))
    }

    func test_install_when_theCocoaPodsFromTheSystemCanBeUsed() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let cocoapods = CocoaPodsNode.test()
        cache.add(cocoapods: cocoapods)

        system.errorCommand(["bundle", "show", "cocoapods"])
        system.whichStub = {
            if $0 == "pod" { return "/path/to/pod" }
            else { throw NSError.test() }
        }
        system.succeedCommand(["pod", "install", "--project-directory=\(cocoapods.path.pathString)", "--repo-update"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertTrue(printer.printSectionArgs.contains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)"))
    }
}
