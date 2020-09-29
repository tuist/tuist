import Foundation
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphTests: TuistUnitTestCase {
    func test_init() {
        // Given
        let project = Project.test()

        // Given: Framework A
        let aFrameworkPath = project.path.appending(component: "FrameworkA.framework")
        let aFrameworkNode = FrameworkNode.test(path: aFrameworkPath,
                                                linking: .dynamic,
                                                architectures: [.armv7],
                                                dependencies: [])

        // Given: Framework B
        let bFrameworkPath = project.path.appending(component: "FrameworkB.framework")
        let bFrameworkNode = FrameworkNode.test(path: bFrameworkPath,
                                                linking: .dynamic,
                                                architectures: [.armv7],
                                                dependencies: [.framework(aFrameworkNode)])

        // Given: SDK
        let xctestNode = SDKNode.xctest(platform: .iOS, status: .required)

        // Given: Library
        let libraryPath = project.path.appending(component: "Library.a")
        let libraryHeadersPath = project.path.appending(component: "LibraryHeaders")
        let libraryNode = LibraryNode.test(path: libraryPath,
                                           publicHeaders: libraryHeadersPath,
                                           architectures: [.armv7],
                                           linking: .static,
                                           swiftModuleMap: nil)

        // Given: XCFramework
        let xcframeworkPath = project.path.appending(component: "XCFramework.xcframework")
        let xcframeworkBinaryPath = xcframeworkPath.appending(component: "Binary")
        let xcframeworkNode = XCFrameworkNode.test(path: xcframeworkPath,
                                                   infoPlist: .test(),
                                                   primaryBinaryPath: xcframeworkBinaryPath,
                                                   linking: .dynamic,
                                                   dependencies: [])

        // Given: Package
        let package = Package.remote(url: "https://github.com/tuist/tuist", requirement: .exact("1.0.0"))
        let packageNode = PackageNode(package: package, path: project.path)
        let packageProduct = PackageProductNode(product: "Tuist", path: project.path)

        // Given: A
        let aTarget = Target.test(name: "A", platform: .iOS, product: .framework)
        let aNode = TargetNode.test(project: project, target: aTarget, dependencies: [xctestNode, bFrameworkNode, packageProduct])

        // Given: B
        let bTarget = Target.test(name: "B", platform: .iOS, product: .framework)
        let bNode = TargetNode.test(project: project, target: bTarget, dependencies: [libraryNode])

        // Given: App
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        let appNode = TargetNode.test(project: project, target: appTarget, dependencies: [aNode, bNode, xcframeworkNode])

        // Given: Graph
        let graph = Graph(name: "Graph",
                          entryPath: project.path,
                          entryNodes: [appNode],
                          projects: [project],
                          cocoapods: [],
                          packages: [packageNode],
                          precompiled: [xcframeworkNode, libraryNode],
                          targets: [project.path: [appNode, aNode, bNode]])

        // When
        let valueGraph = ValueGraph(graph: graph)

        // Then
        XCTAssertEqual(valueGraph.name, graph.name)
        XCTAssertEqual(valueGraph.path, graph.entryPath)
        XCTAssertEqual(valueGraph.projects, [project.path: project])
        XCTAssertEqual(valueGraph.packages, [project.path: [packageNode.name: package]])
        XCTAssertEqual(valueGraph.targets, [project.path: [
            appNode.target.name: appTarget,
            aNode.target.name: aTarget,
            bNode.target.name: bTarget,
        ]])

        // Then: App -> A
        XCTAssertEqual(valueGraph.dependencies[.target(name: appTarget.name, path: appNode.path)]?
            .contains(.target(name: aTarget.name, path: aNode.path)), true)
        // Then: App -> B
        XCTAssertEqual(valueGraph.dependencies[.target(name: appTarget.name, path: appNode.path)]?
            .contains(.target(name: bTarget.name, path: bNode.path)), true)
        // Then: App -> XCFramework
        XCTAssertEqual(valueGraph.dependencies[.target(name: appTarget.name, path: appNode.path)]?
            .contains(.xcframework(path: xcframeworkNode.path, infoPlist: xcframeworkNode.infoPlist, primaryBinaryPath: xcframeworkNode.primaryBinaryPath, linking: xcframeworkNode.linking)), true)
        // Then: B -> Library
        XCTAssertEqual(valueGraph.dependencies[.target(name: bTarget.name, path: bNode.path)]?
            .contains(.library(path: libraryNode.path, publicHeaders: libraryNode.publicHeaders, linking: libraryNode.linking, architectures: libraryNode.architectures, swiftModuleMap: libraryNode.swiftModuleMap)), true)
        // Then: A -> XCTest
        XCTAssertEqual(valueGraph.dependencies[.target(name: aTarget.name, path: aNode.path)]?
            .contains(.sdk(name: xctestNode.name, path: xctestNode.path, status: xctestNode.status, source: xctestNode.source)), true)
        // Then: A -> BFramework
        XCTAssertEqual(valueGraph.dependencies[.target(name: aTarget.name, path: aNode.path)]?
            .contains(.framework(path: bFrameworkNode.path,
                                 dsymPath: bFrameworkNode.dsymPath,
                                 bcsymbolmapPaths: bFrameworkNode.bcsymbolmapPaths,
                                 linking: bFrameworkNode.linking,
                                 architectures: bFrameworkNode.architectures)), true)
        // Then: A -> Package
        XCTAssertEqual(valueGraph.dependencies[.target(name: aTarget.name, path: aNode.path)]?
            .contains(.packageProduct(path: packageProduct.path, product: packageProduct.product)), true)
        // Then: BFramework -> AFramework
        XCTAssertEqual(valueGraph.dependencies[.framework(path: bFrameworkNode.path,
                                                          dsymPath: bFrameworkNode.dsymPath,
                                                          bcsymbolmapPaths: bFrameworkNode.bcsymbolmapPaths,
                                                          linking: bFrameworkNode.linking,
                                                          architectures: bFrameworkNode.architectures)]?
            .contains(.framework(path: aFrameworkNode.path,
                                 dsymPath: aFrameworkNode.dsymPath,
                                 bcsymbolmapPaths: aFrameworkNode.bcsymbolmapPaths,
                                 linking: aFrameworkNode.linking,
                                 architectures: aFrameworkNode.architectures)), true)
        // then: AFramework
        XCTAssertNotNil(valueGraph.dependencies[.framework(path: aFrameworkNode.path,
                                                           dsymPath: aFrameworkNode.dsymPath,
                                                           bcsymbolmapPaths: aFrameworkNode.bcsymbolmapPaths,
                                                           linking: aFrameworkNode.linking,
                                                           architectures: aFrameworkNode.architectures)])

        // Then: XCTest
        XCTAssertNotNil(valueGraph.dependencies[.sdk(name: xctestNode.name, path: xctestNode.path, status: xctestNode.status, source: xctestNode.source)])

        // Then: Library
        XCTAssertNotNil(valueGraph.dependencies[.library(path: libraryNode.path,
                                                         publicHeaders: libraryNode.publicHeaders,
                                                         linking: libraryNode.linking,
                                                         architectures: libraryNode.architectures,
                                                         swiftModuleMap: libraryNode.swiftModuleMap)])
    }
}
