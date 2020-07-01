//import Foundation
//import TuistCore
//import XCTest
//
//@testable import TuistCache
//@testable import TuistCoreTesting
//@testable import TuistSupportTesting
//
//// To generate the ASCII graphs: http://asciiflow.com/
//// Alternative: https://dot-to-ascii.ggerganov.com/
//final class CacheGraphMapperTests: TuistUnitTestCase {
//    var xcframeworkLoader: MockXCFrameworkNodeLoader!
//    var subject: CacheGraphMapper!
//
//    override func setUp() {
//        xcframeworkLoader = MockXCFrameworkNodeLoader()
//        subject = CacheGraphMapper(xcframeworkLoader: xcframeworkLoader)
//        super.setUp()
//    }
//
//    override func tearDown() {
//        super.tearDown()
//        xcframeworkLoader = nil
//        subject = nil
//    }
//
//    // First scenario
//    //       +---->B (Cached Framework)+
//    //       |                         |
//    //    App|                         +------>D (Cached Framework)
//    //       |                         |
//    //       +---->C (Cached Framework)+
//    func test_map_when_first_scenario() throws {
//        let path = try temporaryPath()
//
//        // Given nodes
//        let dFramework = TargetNode.test(target: Target.test(name: "D", platform: .iOS, product: .framework))
//        let bFramework = TargetNode.test(target: Target.test(name: "B", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let cFramework = TargetNode.test(target: Target.test(name: "C", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let appTarget = TargetNode.test(target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFramework, cFramework])
//        let graph = Graph.test(entryNodes: [appTarget])
//
//        // Given xcframeworks
//        let dXCFrameworkPath = path.appending(component: "D.xcframework")
//        let dXCFramework = XCFrameworkNode.test(path: dXCFrameworkPath)
//        let bXCFrameworkPath = path.appending(component: "B.xcframework")
//        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
//        let cXCFrameworkPath = path.appending(component: "C.xcframework")
//        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
//        let xcframeworks = [
//            dFramework: dXCFrameworkPath,
//            bFramework: bXCFrameworkPath,
//            cFramework: cXCFrameworkPath,
//        ]
//
//        xcframeworkLoader.loadStub = { path in
//            if path == dXCFrameworkPath { return dXCFramework }
//            else if path == bXCFrameworkPath { return bXCFramework }
//            else if path == cXCFrameworkPath { return cXCFramework }
//            else { fatalError("Unexpected load call") }
//        }
//
//        // When
//        let got = try subject.map(graph: graph, xcframeworks: xcframeworks)
//
//        // Then
//        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
//        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
//        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
//        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dXCFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dXCFrameworkPath }))
//    }
//
//    // Second scenario
//    //       +---->B (Cached Framework)+
//    //       |                         |
//    //    App|                         +------>D Precompiled .framework
//    //       |                         |
//    //       +---->C (Cached Framework)+
//    func test_map_when_second_scenario() throws {
//        let path = try temporaryPath()
//
//        // Given nodes
//        let dFrameworkPath = path.appending(component: "D.framework")
//        let dFramework = FrameworkNode.test(path: dFrameworkPath)
//        let bFramework = TargetNode.test(target: Target.test(name: "B", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let cFramework = TargetNode.test(target: Target.test(name: "C", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let appTarget = TargetNode.test(target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFramework, cFramework])
//        let graph = Graph.test(entryNodes: [appTarget])
//
//        // Given xcframeworks
//        let bXCFrameworkPath = path.appending(component: "B.xcframework")
//        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
//        let cXCFrameworkPath = path.appending(component: "C.xcframework")
//        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
//        let xcframeworks = [
//            bFramework: bXCFrameworkPath,
//            cFramework: cXCFrameworkPath,
//        ]
//
//        xcframeworkLoader.loadStub = { path in
//            if path == bXCFrameworkPath { return bXCFramework }
//            else if path == cXCFrameworkPath { return cXCFramework }
//            else { fatalError("Unexpected load call") }
//        }
//
//        // When
//        let got = try subject.map(graph: graph, xcframeworks: xcframeworks)
//
//        // Then
//        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
//        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
//        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
//        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
//    }
//
//    // Third scenario
//    //       +---->B (Cached Framework)+
//    //       |                         |
//    //    App|                         +------>D Precompiled .framework
//    //       |                         |
//    //       +---->C (Cached Framework)+------>E Precompiled .xcframework
//    func test_map_when_third_scenario() throws {
//        let path = try temporaryPath()
//
//        // Given nodes
//        let eXCFrameworkPath = path.appending(component: "E.xcframework")
//        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)
//        let dFrameworkPath = path.appending(component: "D.framework")
//        let dFramework = FrameworkNode.test(path: dFrameworkPath)
//        let bFramework = TargetNode.test(target: Target.test(name: "B", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let cFramework = TargetNode.test(target: Target.test(name: "C", platform: .iOS, product: .framework), dependencies: [dFramework, eXCFramework])
//        let appTarget = TargetNode.test(target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFramework, cFramework])
//        let graph = Graph.test(entryNodes: [appTarget])
//
//        // Given xcframeworks
//        let bXCFrameworkPath = path.appending(component: "B.xcframework")
//        let bXCFramework = XCFrameworkNode.test(path: bXCFrameworkPath)
//        let cXCFrameworkPath = path.appending(component: "C.xcframework")
//        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
//        let xcframeworks = [
//            bFramework: bXCFrameworkPath,
//            cFramework: cXCFrameworkPath,
//        ]
//
//        xcframeworkLoader.loadStub = { path in
//            if path == bXCFrameworkPath { return bXCFramework }
//            else if path == cXCFrameworkPath { return cXCFramework }
//            else { fatalError("Unexpected load call") }
//        }
//
//        // When
//        let got = try subject.map(graph: graph, xcframeworks: xcframeworks)
//
//        // Then
//        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
//        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == bXCFrameworkPath }))
//        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
//        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == dFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
//    }
//
//    // Fourth scenario
//    //       +---->B (Framework)+------>D Precompiled .framework
//    //       |
//    //    App|
//    //       |
//    //       +---->C (Cached Framework)+------>E Precompiled .xcframework
//    func test_map_when_fourth_scenario() throws {
//        let path = try temporaryPath()
//
//        // Given nodes
//        let eXCFrameworkPath = path.appending(component: "E.xcframework")
//        let eXCFramework = XCFrameworkNode.test(path: eXCFrameworkPath)
//        let dFrameworkPath = path.appending(component: "D.framework")
//        let dFramework = FrameworkNode.test(path: dFrameworkPath)
//        let bFramework = TargetNode.test(target: Target.test(name: "B", platform: .iOS, product: .framework), dependencies: [dFramework])
//        let cFramework = TargetNode.test(target: Target.test(name: "C", platform: .iOS, product: .framework), dependencies: [eXCFramework])
//        let appTarget = TargetNode.test(target: Target.test(name: "App", platform: .iOS, product: .app), dependencies: [bFramework, cFramework])
//        let graph = Graph.test(entryNodes: [appTarget])
//
//        // Given xcframeworks
//        let cXCFrameworkPath = path.appending(component: "C.xcframework")
//        let cXCFramework = XCFrameworkNode.test(path: cXCFrameworkPath)
//        let xcframeworks = [
//            cFramework: cXCFrameworkPath,
//        ]
//
//        xcframeworkLoader.loadStub = { path in
//            if path == cXCFrameworkPath { return cXCFramework }
//            else { fatalError("Unexpected load call") }
//        }
//
//        // When
//        let got = try subject.map(graph: graph, xcframeworks: xcframeworks)
//
//        // Then
//        let app = try XCTUnwrap(got.entryNodes.first as? TargetNode)
//        let b = try XCTUnwrap(app.dependencies.compactMap { $0 as? TargetNode }.first(where: { $0.name == "B" }))
//        let c = try XCTUnwrap(app.dependencies.compactMap { $0 as? XCFrameworkNode }.first(where: { $0.path == cXCFrameworkPath }))
//        XCTAssertTrue(b.dependencies.contains(where: { $0.path == dFrameworkPath }))
//        XCTAssertTrue(c.dependencies.contains(where: { $0.path == eXCFrameworkPath }))
//    }
//}
