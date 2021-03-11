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
                base: ["a": .string("b")],
                debug: Configuration(
                    settings: ["a": .string("b")],
                    xcconfig: "config"
                ),
                release: Configuration(
                    settings: ["a": .string("b")],
                    xcconfig: "config"
                )
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
            sources: SourceFilesList(globs: ["sources/*"]),
            resources: ["resources/*",
                        .glob(pattern: "file.type", tags: ["tag"]),
                        .folderReference(path: "resource/", tags: ["tag"])],
            headers: Headers(
                public: ["public/*"],
                private: ["private/*"],
                project: ["project/*"]
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
                base: ["a": .string("b")],
                debug: Configuration(
                    settings: ["a": .string("b")],
                    xcconfig: "config"
                ),
                release: Configuration(
                    settings: ["a": .string("b")],
                    xcconfig: "config"
                )
            ),
            coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
            environment: ["a": "b"]
        )
        XCTAssertCodable(subject)
    }
}
