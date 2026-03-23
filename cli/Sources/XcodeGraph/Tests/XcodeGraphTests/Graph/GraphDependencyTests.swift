import Foundation
import Testing
@testable import XcodeGraph

struct GraphDependencyTests {
    @Test func test_codable_target() throws {
        // Given
        let subject = GraphDependency.testTarget()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(GraphDependency.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_framework() throws {
        // Given
        let subject = GraphDependency.testFramework()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(GraphDependency.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_isLinkable() {
        #expect(!GraphDependency.testMacro().isLinkable)
        #expect(GraphDependency.testXCFramework().isLinkable)
        #expect(GraphDependency.testFramework().isLinkable)
        #expect(GraphDependency.testLibrary().isLinkable)
        #expect(!GraphDependency.testBundle().isLinkable)
        #expect(GraphDependency.testPackageProduct().isLinkable)
        #expect(GraphDependency.testTarget().isLinkable)
        #expect(GraphDependency.testSDK().isLinkable)
    }

    @Test func test_isPrecompiledMacro() {
        #expect(GraphDependency.testMacro().isPrecompiledMacro)
        #expect(!GraphDependency.testXCFramework().isPrecompiledMacro)
        #expect(!GraphDependency.testFramework().isPrecompiledMacro)
        #expect(!GraphDependency.testLibrary().isPrecompiledMacro)
        #expect(!GraphDependency.testBundle().isPrecompiledMacro)
        #expect(!GraphDependency.testPackageProduct().isPrecompiledMacro)
        #expect(!GraphDependency.testTarget().isPrecompiledMacro)
        #expect(!GraphDependency.testSDK().isPrecompiledMacro)
    }
}
