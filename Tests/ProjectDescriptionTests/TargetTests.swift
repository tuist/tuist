import Foundation
@testable import ProjectDescription
import XCTest

final class TargetTests: XCTestCase {
    func test_toJSON() {
        let subject = Target(name: "name",
                             platform: .iOS,
                             product: .app,
                             bundleId: "bundle_id",
                             infoPlist: "info.plist",
                             sources: "sources/*",
                             resources: ["resources/*"],
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

        let expected = "{\"bundle_id\": \"bundle_id\", \"core_data_models\": [{\"current_version\": \"version\", \"path\": \"pat\"}], \"dependencies\": [{\"path\": \"path\", \"type\": \"framework\"}, {\"path\": \"path\", \"public_headers\": \"public\", \"swift_module_map\": \"module\", \"type\": \"library\"}, {\"path\": \"path\", \"target\": \"target\", \"type\": \"project\"}, {\"name\": \"name\", \"type\": \"target\"}], \"entitlements\": \"entitlement\", \"headers\": {\"private\": \"private/*\", \"project\": \"project/*\", \"public\": \"public/*\"}, \"info_plist\": \"info.plist\", \"name\": \"name\", \"platform\": \"ios\", \"product\": \"app\", \"resources\": [\"resources/*\"], \"settings\": {\"base\": {\"a\": \"b\"}, \"debug\": {\"settings\": {\"a\": \"b\"}, \"xcconfig\": \"config\"}, \"release\": {\"settings\": {\"a\": \"b\"}, \"xcconfig\": \"config\"}}, \"sources\": \"sources/*\", \"actions\": [ { \"path\": \"path\", \"arguments\": [\"arg\"], \"name\": \"name\", \"order\": \"post\"}], \"environment\": {\"a\": \"b\"}}"
        assertCodableEqualToJson(subject, expected)
    }
}
