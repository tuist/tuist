import Foundation
import Testing
@testable import TuistCore

struct TestIdentifierTests {
    @Test func test_should_failToInitialize_when_targetEmpty_usingIndividualComponents() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(target: "") }
    }

    @Test func test_should_failToInitialize_when_classEmpty_usingIndividualComponents() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(target: "target", class: "") }
    }

    @Test func test_should_failToInitialize_when_methodEmpty_usingIndividualComponents() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(target: "target", class: "class", method: "") }
    }

    @Test func test_should_initialize_when_targetSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target")
        #expect(testIdentifier.description == "target")
    }

    @Test func test_should_initialize_when_targetClassSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class")
        #expect(testIdentifier.description == "target/class")
    }

    @Test func test_should_initialize_when_targetClassMethodSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class", method: "method")
        #expect(testIdentifier.description == "target/class/method")
    }

    @Test func test_should_failToInitialize_when_targetEmpty_usingString() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(string: "") }
    }

    @Test func test_should_failToInitialize_when_classEmpty_usingString() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(string: "target/") }
    }

    @Test func test_should_failToInitialize_when_methodEmpty_usingString() throws {
        #expect(throws: (any Error).self) { try TestIdentifier(string: "target/class/") }
    }

    @Test func test_should_failToInitialize_when_targetMethodSpecifiedButNotClass_usingString() {
        #expect(throws: (any Error).self) { try TestIdentifier(string: "target//method") }
    }

    @Test func test_should_initialize_when_targetSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target")
        #expect(testIdentifier.description == "target")
    }

    @Test func test_should_initialize_when_targetClassSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target/class")
        #expect(testIdentifier.description == "target/class")
    }

    @Test func test_should_initialize_when_targetClassMethodSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(target: "target/class/method")
        #expect(testIdentifier.description == "target/class/method")
    }
}
