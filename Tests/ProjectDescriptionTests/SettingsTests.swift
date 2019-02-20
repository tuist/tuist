import Foundation
@testable import ProjectDescription
import XCTest

final class SettingsTests: XCTestCase {
    
    func test_toJSON() {
        
        let expected =
        """
{
    "base": {
        "base": "base"
    },
    "configurations": [
        {
            "settings": {
                "debug": "debug"
            },
            "name": "Debug",
            "buildConfiguration": "debug",
            "xcconfig": "/path/debug.xcconfig"
        },
        {
            "settings": {
                "release": "release"
            },
            "name": "Release",
            "buildConfiguration": "release",
            "xcconfig": "/path/release.xcconfig"
        }
    ]
}
"""
        
        let subject = Settings(
            base: ["base": "base"],
            configurations: [
                .debug(name: "Debug", settings: ["debug": "debug"], xcconfig: "/path/debug.xcconfig"),
                .release(name: "Release", settings: ["release": "release"], xcconfig: "/path/release.xcconfig")
            ]
        )

        assertCodableEqualToJson(subject, expected)
    }
    
    func test_toJSON_array() {
        
        let expected =
        """
{
    "base": {
        "base": "base"
    },
    "configurations": [
        {
            "settings": {
                "debug": "debug"
            },
            "name": "Debug",
            "buildConfiguration": "debug",
            "xcconfig": "/path/debug.xcconfig"
        },
        {
            "settings": {
                "release": "release"
            },
            "name": "Release",
            "buildConfiguration": "release",
            "xcconfig": "/path/release.xcconfig"
        }
    ]
}
"""
        
        let subject = Settings(
            base: [ "base": "base" ],
            configurations: [
                .debug(name: "Debug", settings: [ "debug": "debug" ], xcconfig: "/path/debug.xcconfig"),
                .release(name: "Release", settings: [ "release": "release" ], xcconfig: "/path/release.xcconfig")
            ]
        )

        assertCodableEqualToJson(subject, expected)
    }

}
