import Foundation
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistTesting

struct GraphDependencyTests {
    @Test func test_isTarget() {
        #expect(!GraphDependency.testXCFramework().isTarget)
        #expect(!GraphDependency.testFramework().isTarget)
        #expect(!GraphDependency.testLibrary().isTarget)
        #expect(!GraphDependency.testPackageProduct().isTarget)
        #expect(GraphDependency.testTarget().isTarget)
        #expect(!GraphDependency.testSDK().isTarget)
    }

    @Test func test_isPrecompiled() {
        #expect(GraphDependency.testXCFramework().isPrecompiled)
        #expect(GraphDependency.testFramework().isPrecompiled)
        #expect(GraphDependency.testLibrary().isPrecompiled)
        #expect(!GraphDependency.testPackageProduct().isPrecompiled)
        #expect(!GraphDependency.testTarget().isPrecompiled)
        #expect(!GraphDependency.testSDK().isPrecompiled)
    }

    @Test func test_isStaticPrecompiled() {
        #expect(GraphDependency.testXCFramework(linking: .static).isStaticPrecompiled)
        #expect(GraphDependency.testFramework(linking: .static).isStaticPrecompiled)
        #expect(GraphDependency.testLibrary(linking: .static).isStaticPrecompiled)
        #expect(!GraphDependency.testPackageProduct().isStaticPrecompiled)
        #expect(!GraphDependency.testTarget().isStaticPrecompiled)
        #expect(!GraphDependency.testSDK().isStaticPrecompiled)
    }

    @Test func test_isDynamicPrecompiled() {
        #expect(GraphDependency.testXCFramework(linking: .dynamic).isDynamicPrecompiled)
        #expect(GraphDependency.testFramework(linking: .dynamic).isDynamicPrecompiled)
        #expect(GraphDependency.testLibrary(linking: .dynamic).isDynamicPrecompiled)
        #expect(!GraphDependency.testPackageProduct().isDynamicPrecompiled)
        #expect(!GraphDependency.testTarget().isDynamicPrecompiled)
        #expect(!GraphDependency.testSDK().isDynamicPrecompiled)
    }
}
