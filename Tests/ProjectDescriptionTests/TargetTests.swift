import Foundation
import XCTest
@testable import ProjectDescription

final class TargetTests: XCTestCase {
    func test_toJSON() {
        let subject = Target(name: "name",
                             platform: .iOS,
                             product: .app,
                             bundleId: "bundle_id",
                             infoPlist: "info.plist",
                             mainStoryboard: "Main",
                             launchScreenStoryboard: "Launch Screen",
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
                             settings: Settings(base: ["a": "b"],
                                                debug: Configuration(settings: ["a": "b"],
                                                                     xcconfig: "config"),
                                                release: Configuration(settings: ["a": "b"],
                                                                       xcconfig: "config")),
                             coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
                             environment: ["a": "b"])

        let expected = "{\"main_storyboard\":\"Main\",\"headers\":{\"public\":\"public\\/*\",\"private\":\"private\\/*\",\"project\":\"project\\/*\"},\"bundle_id\":\"bundle_id\",\"core_data_models\":[{\"path\":\"pat\",\"current_version\":\"version\"}],\"actions\":[{\"arguments\":[\"arg\"],\"path\":\"path\",\"order\":\"post\",\"name\":\"name\"}],\"product\":\"app\",\"sources\":{\"globs\":[\"sources\\/*\"]},\"settings\":{\"base\":{\"a\":\"b\"},\"debug\":{\"xcconfig\":\"config\",\"settings\":{\"a\":\"b\"}},\"release\":{\"xcconfig\":\"config\",\"settings\":{\"a\":\"b\"}}},\"resources\":{\"globs\":[\"resources\\/*\"]},\"platform\":\"ios\",\"entitlements\":\"entitlement\",\"info_plist\":\"info.plist\",\"dependencies\":[{\"type\":\"framework\",\"path\":\"path\"},{\"path\":\"path\",\"public_headers\":\"public\",\"swift_module_map\":\"module\",\"type\":\"library\"},{\"type\":\"project\",\"target\":\"target\",\"path\":\"path\"},{\"type\":\"target\",\"name\":\"name\"}],\"launch_screen_storyboard\":\"Launch Screen\",\"environment\":{\"a\":\"b\"},\"name\":\"name\"}"
        assertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_withFileList() {
        let subject = Target(name: "name",
                             platform: .iOS,
                             product: .app,
                             bundleId: "bundle_id",
                             infoPlist: "info.plist",
                             mainStoryboard: "Main",
                             launchScreenStoryboard: "Launch Screen",
                             sources: FileList(globs: ["sources/*"]),
                             resources: FileList(globs: ["resources/*"]),
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
                             settings: Settings(base: ["a": "b"],
                                                debug: Configuration(settings: ["a": "b"],
                                                                     xcconfig: "config"),
                                                release: Configuration(settings: ["a": "b"],
                                                                       xcconfig: "config")),
                             coreDataModels: [CoreDataModel("pat", currentVersion: "version")],
                             environment: ["a": "b"])

        let expected = "{\"main_storyboard\":\"Main\",\"headers\":{\"public\":\"public\\/*\",\"private\":\"private\\/*\",\"project\":\"project\\/*\"},\"bundle_id\":\"bundle_id\",\"core_data_models\":[{\"path\":\"pat\",\"current_version\":\"version\"}],\"actions\":[{\"arguments\":[\"arg\"],\"path\":\"path\",\"order\":\"post\",\"name\":\"name\"}],\"product\":\"app\",\"sources\":{\"globs\":[\"sources\\/*\"]},\"settings\":{\"base\":{\"a\":\"b\"},\"debug\":{\"xcconfig\":\"config\",\"settings\":{\"a\":\"b\"}},\"release\":{\"xcconfig\":\"config\",\"settings\":{\"a\":\"b\"}}},\"resources\":{\"globs\":[\"resources\\/*\"]},\"platform\":\"ios\",\"entitlements\":\"entitlement\",\"info_plist\":\"info.plist\",\"dependencies\":[{\"type\":\"framework\",\"path\":\"path\"},{\"path\":\"path\",\"public_headers\":\"public\",\"swift_module_map\":\"module\",\"type\":\"library\"},{\"type\":\"project\",\"target\":\"target\",\"path\":\"path\"},{\"type\":\"target\",\"name\":\"name\"}],\"launch_screen_storyboard\":\"Launch Screen\",\"environment\":{\"a\":\"b\"},\"name\":\"name\"}"
        assertCodableEqualToJson(subject, expected)
    }
}
