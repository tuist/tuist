import Foundation
import XCTest
@testable import TuistCore

final class TestIdentifierTests: XCTestCase {
    func test_should_failToInitialize_when_targetEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: ""))
    }

    func test_should_failToInitialize_when_classEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: "target", class: ""))
    }

    func test_should_failToInitialize_when_methodEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: "target", class: "class", method: ""))
    }

    func test_should_initialize_when_targetSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target")
        XCTAssertEqual(testIdentifier.description, "target")
    }

    func test_should_initialize_when_targetClassSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class")
        XCTAssertEqual(testIdentifier.description, "target/class")
    }

    func test_should_initialize_when_targetClassMethodSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class", method: "method")
        XCTAssertEqual(testIdentifier.description, "target/class/method")
    }

    func test_should_failToInitialize_when_targetEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: ""))
    }

    func test_should_failToInitialize_when_classEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: "target/"))
    }

    func test_should_failToInitialize_when_methodEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: "target/class/"))
    }

    func test_should_failToInitialize_when_targetMethodSpecifiedButNotClass_usingString() {
        try XCTAssertThrowsError(TestIdentifier(string: "target//method"))
    }

    func test_should_initialize_when_targetSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target")
        XCTAssertEqual(testIdentifier.description, "target")
    }

    func test_should_initialize_when_targetClassSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target/class")
        XCTAssertEqual(testIdentifier.description, "target/class")
    }

    func test_should_initialize_when_targetClassMethodSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(target: "target/class/method")
        XCTAssertEqual(testIdentifier.description, "target/class/method")
    }
}
