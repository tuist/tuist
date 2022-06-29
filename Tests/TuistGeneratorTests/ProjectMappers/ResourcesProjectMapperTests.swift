import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

// Bundle name is irrelevant if the target supports resources.
private let irrelevantBundleName = ""

final class ResourcesProjectMapperTests: TuistUnitTestCase {
    var project: Project!
    var subject: ResourcesProjectMapper!
    var contentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        contentHasher = MockContentHasher()
        subject = ResourcesProjectMapper(contentHasher: contentHasher)
    }

    override func tearDown() {
        project = nil
        subject = nil
        super.tearDown()
    }

    func test_map_when_a_target_that_has_resources_and_doesnt_supports_them() throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
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
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target)
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
        XCTAssertNotNil(gotTarget.sources.first?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(gotTarget.dependencies.first, TargetDependency.target(name: "\(project.name)_\(target.name)"))

        let resourcesTarget = try XCTUnwrap(gotProject.targets.last)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.platform, target.platform)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).resources")
        XCTAssertEqual(resourcesTarget.deploymentTarget, target.deploymentTarget)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.resources, resources)
    }

    func testMap_whenDisableBundleAccessorsIsTrue_doesNotGenerateAccessors() throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, resources: resources)
        project = Project.test(
            options: .test(
                disableBundleAccessors: true
            ),
            targets: [target]
        )

        // Got
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(project, gotProject)
        XCTAssertEqual(gotSideEffects, [])
    }

    func test_map_when_a_target_that_has_core_data_models_and_doesnt_supports_them() throws {
        // Given

        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .staticLibrary, coreDataModels: coreDataModels)
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
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target)
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
        XCTAssertNotNil(gotTarget.sources.first?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(gotTarget.dependencies.first, TargetDependency.target(name: "\(project.name)_\(target.name)"))

        let resourcesTarget = try XCTUnwrap(gotProject.targets.last)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.platform, target.platform)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).resources")
        XCTAssertEqual(resourcesTarget.deploymentTarget, target.deploymentTarget)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.coreDataModels, coreDataModels)
    }

    func test_map_when_a_target_that_has_resources_and_supports_them() throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
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
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: irrelevantBundleName, target: target)
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
        XCTAssertNotNil(gotTarget.sources.first?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }

    func test_map_when_a_target_that_has_core_data_models_and_supports_them() throws {
        // Given
        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .framework, coreDataModels: coreDataModels)
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
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: irrelevantBundleName, target: target)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 1)
        let gotTarget = try XCTUnwrap(gotProject.targets.first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.coreDataModels, coreDataModels)
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotTarget.sources.first?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.first?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }

    func test_map_when_a_target_has_no_resources() throws {
        // Given
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .framework, resources: resources)
        project = Project.test(targets: [target])

        // Got
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(gotProject.targets, [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_target_does_not_support_sources() throws {
        // Given
        let resources: [ResourceFileElement] = [
            .file(path: "/Some/ResourceA"),
            .file(path: "/Some/ResourceB"),
        ]
        let target = Target.test(product: .bundle, resources: resources)
        project = Project.test(targets: [target])

        // Got
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(gotProject.targets, [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_target_that_has_name_with_hyphen() throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(name: "test-tuist", product: .staticLibrary, resources: resources)
        project = Project.test(targets: [target])

        // Got
        let (_, gotSideEffects) = try subject.map(project: project)

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
            .appending(component: "TuistBundle+\(target.name.camelized.uppercasingFirst).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_test_tuist", target: target)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))
    }
}
