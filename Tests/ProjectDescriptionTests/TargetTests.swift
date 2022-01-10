import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class TargetTests: XCTestCase {
    func test_toJSON() {
        let subject = Target(
            name: "name",
            platform: .iOS,
            product: .app,
            productName: "product_name",
            bundleId: "bundle_id",
            deploymentTarget: .iOS(targetVersion: "13.1", devices: [.iphone, .ipad]),
            infoPlist: "info.plist",
            sources: "sources/*",
            resources: "resources/*",
            headers: .headers(
                public: "public/*",
                private: "private/*",
                project: "project/*"
            ),
            entitlements: "entitlement",
            scripts: [
                TargetScript.post(path: "path", arguments: ["arg"], name: "name"),
            ],
            dependencies: [
                .framework(path: "path"),
                .library(path: "path", publicHeaders: "public", swiftModuleMap: "module"),
                .project(target: "target", path: "path"),
                .target(name: "name"),
            ],
            settings: .settings(
                base: ["a": .string("b")],
                debug: ["a": .string("b")],
                release: ["a": .string("b")]
            ),
            coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
            environment: ["a": "b"]
        )
        XCTAssertCodable(subject)
    }

    func test_toJSON_withFileList() {
        let subject = Target(
            name: "name",
            platform: .iOS,
            product: .app,
            productName: "product_name",
            bundleId: "bundle_id",
            infoPlist: "info.plist",
            sources: SourceFilesList(globs: [
                "sources/*",
                .glob("Intents/Public.intentdefinition", codeGen: .public),
                .glob("Intents/Private.intentdefinition", codeGen: .private),
                .glob("Intents/Project.intentdefinition", codeGen: .project),
                .glob("Intents/Disabled.intentdefinition", codeGen: .disabled),
            ]),
            resources: [
                "resources/*",
                .glob(pattern: "file.type", tags: ["tag"]),
                .folderReference(path: "resource/", tags: ["tag"]),
            ],
            headers: .headers(
                public: ["public/*"],
                private: ["private/*"],
                project: ["project/*"]
            ),
            entitlements: "entitlement",
            scripts: [
                TargetScript.post(path: "path", arguments: ["arg"], name: "name"),
            ],
            dependencies: [
                .framework(path: "path"),
                .library(path: "path", publicHeaders: "public", swiftModuleMap: "module"),
                .project(target: "target", path: "path"),
                .target(name: "name"),
            ],
            settings: .settings(
                base: ["a": .string("b")],
                configurations: [
                    .debug(name: .debug, settings: ["a": .string("debug")], xcconfig: "debug.xcconfig"),
                    .debug(name: "Beta", settings: ["a": .string("beta")], xcconfig: "beta.xcconfig"),
                    .debug(name: .release, settings: ["a": .string("release")], xcconfig: "debug.xcconfig"),
                ]
            ),
            coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
            environment: ["a": "b"]
        )
        XCTAssertCodable(subject)
    }
}
