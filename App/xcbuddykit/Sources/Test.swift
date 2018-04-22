import Foundation
import ProjectDescription

let project = ProjectDescription.Project(name: "{{NAME}}",
                                         schemes: [],
                                         targets: [ProjectDescription.Target(name: "target",
                                                                             platform: ProjectDescription.Platform.ios,
                                                                             product: ProjectDescription.Product.app,
                                                                             infoPlist: "info.plist",
                                                                             entitlements: "entitlements",
                                                                             dependencies: [ProjectDescription.TargetDependency.framework(path: "framework")],
                                                                             settings: ProjectDescription.Settings(debug: ProjectDescription.Settings.Configuration(settings: ["a": "b"], xcconfig: "xx.xcconfig"), release: nil), buildPhases: [ProjectDescription.BuildPhase.headers()])], settings: nil, config: nil)
