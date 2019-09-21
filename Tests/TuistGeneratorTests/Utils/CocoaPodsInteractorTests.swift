import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

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

final class CocoaPodsInteractorTests: XCTestCase {
    var system: MockSystem!
    var subject: CocoaPodsInteractor!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()

        system = MockSystem()
        subject = CocoaPodsInteractor(system: system)
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
        system.succeedCommand(["bundle", "exec", "pod", "install", "--project-directory=\(cocoapods.path.pathString)"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)")
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
        system.succeedCommand(["pod", "install", "--project-directory=\(cocoapods.path.pathString)"])

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("Installing CocoaPods dependencies defined in \(cocoapods.podfilePath)")
    }

    func test_install_when_theCocoaPodsSpecsRepoIsOutdated() throws {
        // Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let cocoapods = CocoaPodsNode.test()
        cache.add(cocoapods: cocoapods)

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
