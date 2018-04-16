import Foundation
import ProjectDescription

let project = ProjectDescription.Project(name: "name",
                                         schemes: [ProjectDescription.Scheme(name: "scheme",
                                                                             shared: true,
                                                                             buildAction: ProjectDescription.BuildAction(targets: ["build_target"]),
                                                                             testAction: ProjectDescription.TestAction(targets: ["test_target"],
                                                                                                                       arguments: ProjectDescription.Arguments(environment: ["env": "env"], launch: ["a": true]),
                                                                                                                       config: .debug,
                                                                                                                       coverage: true),
                                                                             runAction: ProjectDescription.RunAction(config: .debug,
                                                                                                                     executable: "executable",
                                                                                                                     arguments: ProjectDescription.Arguments(environment: ["env": "env"], launch: ["a": true])))],
                                         targets: [ProjectDescription.Target(name: "target",
                                                                             platform: ProjectDescription.Platform.ios,
                                                                             product: ProjectDescription.Product.app,
                                                                             infoPlist: "info.plist",
                                                                             entitlements: "entitlements",
                                                                             dependencies: [ProjectDescription.TargetDependency.framework(path: "framework")],
                                                                             settings: ProjectDescription.Settings(debug: ProjectDescription.Settings.Configuration(settings: ["a": "b"], xcconfig: "xx.xcconfig"), release: nil), buildPhases: [ProjectDescription.BuildPhase.headers()])], settings: nil, config: nil)
