import Foundation
import ProjectDescription
import XCTest
@testable import TuistLoader

final class SettingsDictionaryDeepMergeTests: XCTestCase {
    func test_deepMerge_whenArraysContainInherited_concatenatesArrays() {
        // Given
        var dict1: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]
        let dict2: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"]),
        ]

        // When
        dict1.deepMerge(dict2)

        // Then
        XCTAssertEqual(
            dict1["OTHER_SWIFT_FLAGS"],
            .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes", "-DSTAGING"])
        )
    }

    func test_deepMerge_whenArrayDoesNotContainInherited_overwritesArray() {
        // Given
        var dict1: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]
        let dict2: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["-DRELEASE"]), // No $(inherited)
        ]

        // When
        dict1.deepMerge(dict2)

        // Then
        XCTAssertEqual(
            dict1["OTHER_SWIFT_FLAGS"],
            .array(["-DRELEASE"])
        )
    }

    func test_deepMerge_whenScalarValue_overwritesScalar() {
        // Given
        var dict1: SettingsDictionary = [
            "MACOSX_DEPLOYMENT_TARGET": .string("12.0"),
        ]
        let dict2: SettingsDictionary = [
            "MACOSX_DEPLOYMENT_TARGET": .string("15.0"),
        ]

        // When
        dict1.deepMerge(dict2)

        // Then
        XCTAssertEqual(
            dict1["MACOSX_DEPLOYMENT_TARGET"],
            .string("15.0")
        )
    }
}
