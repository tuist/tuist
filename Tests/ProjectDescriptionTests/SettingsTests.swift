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
            "type": "debug",
            "xcconfig": "/path/debug.xcconfig"
        },
        {
            "settings": {
                "release": "release"
            },
            "name": "Release",
            "type": "release",
            "xcconfig": "/path/release.xcconfig"
        }
    ]
}
"""
        
        let subject = Settings(
            base: ["base": "base"],
            debug: .debug(["debug": "debug"], xcconfig: "/path/debug.xcconfig"),
            release: .release(["release": "release"], xcconfig: "/path/release.xcconfig")
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
            "type": "debug",
            "xcconfig": "/path/debug.xcconfig"
        },
        {
            "settings": {
                "release": "release"
            },
            "name": "Release",
            "type": "release",
            "xcconfig": "/path/release.xcconfig"
        }
    ]
}
"""
        
        let subject = Settings(
            base: [ "base": "base" ],
            configurations: [
                .debug([ "debug": "debug" ], xcconfig: "/path/debug.xcconfig"),
                .release([ "release": "release" ], xcconfig: "/path/release.xcconfig")
            ]
        )

        assertCodableEqualToJson(subject, expected)
    }
    
    func test_toJSON_array_literal() {
        
        let expected =
        """
{
    "base": { },
    "configurations": [
        {
            "settings": { },
            "name": "Debug",
            "type": "debug",
            "xcconfig": "/path/debug.xcconfig"
        },
        {
            "settings": { },
            "name": "Release",
            "type": "release",
            "xcconfig": "/path/release.xcconfig"
        }
    ]
}
"""
        
        let subject: Settings = [
            .debug(xcconfig: "/path/debug.xcconfig"),
            .release(xcconfig: "/path/release.xcconfig")
        ]
        
        assertCodableEqualToJson(subject, expected)
    }
}
