import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class TargetTests: XCTestCase {
    func test_toJSON() {
        let subject = Target(name: "name",
                             platform: .iOS,
                             product: .app,
                             productName: "product_name",
                             bundleId: "bundle_id",
                             deploymentTarget: .iOS("13.1", [.iphone, .ipad]),
                             infoPlist: "info.plist",
                             sources: "sources/*",
                             resources: "resources/*",
                             headers: Headers(public: "public/*",
                                              private: "private/*",
                                              project: "project/*"),
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
                             settings: Settings(base: ["a": .string("b")],
                                                debug: Configuration(settings: ["a": .string("b")],
                                                                     xcconfig: "config"),
                                                release: Configuration(settings: ["a": .string("b")],
                                                                       xcconfig: "config")),
                             coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
                             environment: ["a": "b"])

        let expected = """
        {
            "deploymentTarget": {
               "kind": "iOS",
               "version": "13.1",
               "deploymentDevices": [1, 2]
            },
            "headers": {
                "public": { "globs": ["public\\/*"] },
                "private": { "globs": ["private\\/*"] },
                "project": { "globs": ["project\\/*"] }
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
            "product_name": "product_name",
            "sources": [
                {
                    "glob": "sources\\/*"
                }
            ],
            "settings": {
                "base": {
                    "a": "b"
                },
                "configurations": [
                    {
                        "name": "Debug",
                        "variant": "debug",
                        "configuration": {
                            "xcconfig": "config",
                            "settings": {
                                "a": "b"
                            }
                        }
                    },
                    {
                        "name": "Release",
                        "variant": "release",
                        "configuration": {
                            "xcconfig": "config",
                            "settings": {
                                "a": "b"
                            }
                        }
                    },
                ],
                "defaultSettings": "recommended"
            },
            "resources": [
                {
                    "type": "glob",
                    "pattern": "resources\\/*"
                }
            ],
            "platform": "ios",
            "entitlements": "entitlement",
            "info_plist": {
                "type": "file",
                "value": "info.plist"
            },
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
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_withFileList() {
        let subject = Target(name: "name",
                             platform: .iOS,
                             product: .app,
                             productName: "product_name",
                             bundleId: "bundle_id",
                             infoPlist: "info.plist",
                             sources: SourceFilesList(globs: ["sources/*"]),
                             resources: ["resources/*"],
                             headers: Headers(public: ["public/*"],
                                              private: ["private/*"],
                                              project: ["project/*"]),
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
                             settings: Settings(base: ["a": .string("b")],
                                                debug: Configuration(settings: ["a": .string("b")],
                                                                     xcconfig: "config"),
                                                release: Configuration(settings: ["a": .string("b")],
                                                                       xcconfig: "config")),
                             coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
                             environment: ["a": "b"])

        let expected = """
        {
            "headers": {
                "public": { "globs": ["public\\/*"] },
                "private": { "globs": ["private\\/*"] },
                "project": { "globs": ["project\\/*"] }
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
            "product_name": "product_name",
            "sources": [
                {
                    "glob": "sources\\/*"
                }
            ],
            "settings": {
                "base": {
                    "a": "b"
                },
                "configurations": [
                    {
                        "name": "Debug",
                        "variant": "debug",
                        "configuration": {
                            "xcconfig": "config",
                            "settings": {
                                "a": "b"
                            }
                        }
                    },
                    {
                        "name": "Release",
                        "variant": "release",
                        "configuration": {
                            "xcconfig": "config",
                            "settings": {
                                "a": "b"
                            }
                        }
                    },
                ],
                "defaultSettings": "recommended"
            },
            "resources": [
                {
                    "type": "glob",
                    "pattern": "resources\\/*"
                }
            ],
            "platform": "ios",
            "entitlements": "entitlement",
            "info_plist": {
                "type": "file",
                "value": "info.plist"
            },
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
        XCTAssertCodableEqualToJson(subject, expected)
    }
}
