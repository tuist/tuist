import Foundation
@testable import ProjectDescription
import XCTest

final class TargetTests: XCTestCase {
    func test_toJSON() {
        
        let subject = Target(
            name: "name",
            platform: .iOS,
            product: .app,
            bundleId: "bundle_id",
            infoPlist: "info.plist",
            sources: "sources/*",
            resources: "resources/*",
            headers: Headers(
                public: "public/*",
                private: "private/*",
                project: "project/*"
            ),
            entitlements: "entitlement",
            actions: [
                TargetAction.post(path: "path", arguments: ["arg"], name: "name"),
            ],
            dependencies: [
                .framework(path: "path"),
                .library(path: "path", publicHeaders: "public", swiftModuleMap: "module"),
                .project(target: "target", path: "path"),
                .target(name: "name"),
            ],
            settings: Settings(
                base: ["base": "base"],
                configurations: [
                    .debug(name: "Debug", settings: ["debug": "debug"], xcconfig: "/path/debug.xcconfig"),
                    .release(name: "Release", settings: ["release": "release"], xcconfig: "/path/release.xcconfig")
                ]
            ),
            coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
            environment: ["a": "b"]
        )
        
        let expected =
"""
{
    "headers": {
        "public": "public/*",
        "private": "private/*",
        "project": "project/*"
    },
    "bundle_id": "bundle_id",
    "core_data_models": [
        {
            "path": "pat",
            "current_version": "version"
        }
    ],
    "actions": [
        {
            "arguments": [
                "arg"
            ],
            "path": "path",
            "order": "post",
            "name": "name"
        }
    ],
    "product": "app",
    "sources": "sources/*",
    "settings": {
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
    },
    "resources": "resources/*",
    "platform": "ios",
    "entitlements": "entitlement",
    "info_plist": "info.plist",
    "dependencies": [
        {
            "type": "framework",
            "path": "path"
        },
        {
            "path": "path",
            "public_headers": "public",
            "swift_module_map": "module",
            "type": "library"
        },
        {
            "type": "project",
            "target": "target",
            "path": "path"
        },
        {
            "type": "target",
            "name": "name"
        }
    ],
    "environment": {
        "a": "b"
    },
    "name": "name"
}
"""

        assertCodableEqualToJson(subject, expected)
    }
}
