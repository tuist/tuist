import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class ResourcesProjectMapperTests: TuistUnitTestCase {
    var project: Project!
    var subject: ResourcesProjectMapper!

    override func setUp() {
        super.setUp()
        subject = ResourcesProjectMapper()
    }

    override func tearDown() {
        super.tearDown()
        project = nil
        subject = nil
    }

    func test_map_when_a_target_that_has_resources_and_doesnt_supports_them() throws {
        // Given
        let resources: [FileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, resources: resources)
        project = Project.test(targets: [target])

        // Got
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "Bundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(target.name)Resources")
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 2)
        let gotTarget = try XCTUnwrap(gotProject.targets.first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotTarget.sources.first?.path, expectedPath)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(gotTarget.dependencies.first, Dependency.target(name: "\(target.name)Resources"))

        let resourcesTarget = try XCTUnwrap(gotProject.targets.last)
        XCTAssertEqual(resourcesTarget.name, "\(target.name)Resources")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.platform, target.platform)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).resources")
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.resources, resources)
    }

    func test_map_when_a_target_that_has_resources_and_supports_them() throws {
        // Given
        let resources: [FileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .framework, resources: resources)
        project = Project.test(targets: [target])

        // Got
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "Bundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(target.name)Resources")
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 1)
        let gotTarget = try XCTUnwrap(gotProject.targets.first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources, resources)
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotTarget.sources.first?.path, expectedPath)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }
}
