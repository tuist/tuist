//
//  Project+Builder.swift
//  ProjectDescription
//
//  Created by Luis Padron on 1/4/22.
//

import Foundation

// Goal:
// let project = Project(name: "MyProject") {
//    Target(
//        name: "TopLevelTarget",
//        platform: .iOS,
//        product: .framework,
//        bundleId: "com.tuist.Target"
//    )
//
//    Scheme(name: "SchemeA")
//        .build {
//            Target(
//                name: "TargetA",
//                platform: .iOS,
//                product: .framework,
//                bundleId: "com.tuist.Target"
//            )
//        }
//        .test {
//            Target(
//                name: "TargetB",
//                platform: .iOS,
//                product: .framework,
//                bundleId: "com.tuist.Target"
//            )
//        }
// }

let project = Project(name: "MyProject") {
    Target(
        name: "TargetA",
        platform: .iOS,
        product: .framework,
        bundleId: "com.tuist.Target"
    )

    Scheme(name: "SchemeA")
        .build {
            Target(
                name: "TargetB",
                platform: .iOS,
                product: .framework,
                bundleId: "com.tuist.Target"
            )
        }
        .test {
            Target(
                name: "TestTarget",
                platform: .iOS,
                product: .unitTests,
                bundleId: "com.tuist.Target"
            )
        }
}

//    Target(
//        name: <#T##String#>,
//        platform: <#T##Platform#>,
//        product: <#T##Product#>,
//        productName: <#T##String?#>,
//        bundleId: <#T##String#>,
//        deploymentTarget: <#T##DeploymentTarget?#>,
//        infoPlist: <#T##InfoPlist#>,
//        sources: <#T##SourceFilesList?#>,
//        resources: <#T##ResourceFileElements?#>,
//        copyFiles: <#T##[CopyFilesAction]?#>,
//        headers: <#T##Headers?#>,
//        entitlements: <#T##Path?#>,
//        scripts: <#T##[TargetScript]#>,
//        dependencies: [],
//        settings: <#T##Settings?#>,
//        coreDataModels: <#T##[CoreDataModel]#>,
//        environment: <#T##[String : String]#>,
//        launchArguments: <#T##[LaunchArgument]#>,
//        additionalFiles: <#T##[FileElement]#>
//    )

extension Project {
    public init(
        name: String,
        @ProjectItemsBuilder _ items: @escaping () -> [ProjectItem]
    ) {
        self = ProjectBuilder(
            name: name,
            items
        ).build()
    }
}

public struct ProjectBuilder {
    let name: String
    let items: () -> [ProjectItem]

    public init(
        name: String,
        @ProjectItemsBuilder _ items: @escaping () -> [ProjectItem]
    ) {
        self.name = name
        self.items = items
    }

    func build() -> Project {
        var project = Project(name: name)
        items().forEach { $0.map(&project) }
        return project
    }
}
