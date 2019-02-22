import Foundation
@testable import ProjectDescription

extension Workspace {
    static func test(name: String = "Workspace",
                     projects: [String] = []) -> Workspace {
        return Workspace(name: name,
                         projects: projects)
    }
}

extension Project {
    static func test(name: String = "Project",
                     settings: Settings? = nil,
                     targets: [Target] = []) -> Project {
        return Project(name: name,
                       settings: settings,
                       targets: targets)
    }
}

extension Target {
    static func test(name: String = "Target",
                     platform: Platform = .iOS,
                     product: Product = .framework,
                     bundleId: String = "com.some.bundle.id",
                     infoPlist: String = "Info.plist",
                     sources: String = "Sources/**",
                     resources: String = "Resources/**",
                     headers: Headers? = nil,
                     entitlements: String? = "app.entitlements",
                     actions: [TargetAction] = [],
                     dependencies: [TargetDependency] = [],
                     settings: Settings? = nil,
                     coreDataModels: [CoreDataModel] = [],
                     environment: [String: String] = [:]) -> Target {
        return Target(name: name,
                      platform: platform,
                      product: product,
                      bundleId: bundleId,
                      infoPlist: infoPlist,
                      sources: sources,
                      resources: resources,
                      headers: headers,
                      entitlements: entitlements,
                      actions: actions,
                      dependencies: dependencies,
                      settings: settings,
                      coreDataModels: coreDataModels,
                      environment: environment)
    }
}

extension TargetAction {
    static func test(name: String = "Action",
                     tool: String? = nil,
                     path: String? = nil,
                     order: Order = .pre,
                     arguments: [String] = []) -> TargetAction {
        return TargetAction(name: name,
                            tool: tool,
                            path: path,
                            order: order,
                            arguments: arguments)
    }
}
