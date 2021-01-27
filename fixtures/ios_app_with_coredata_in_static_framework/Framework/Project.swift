import ProjectDescription

let project = Project(name: "MyFramework",
                      targets: [
                        Target(name: "MyFramework",
                             platform: .iOS,
                             product: .framework,
                             bundleId: "io.tuist.framework",
                             infoPlist: .default,
                             sources: ["Sources/Model.swift"],
                             coreDataModels: [
                               CoreDataModel("CoreData/Users.xcdatamodeld", currentVersion: "1")
                             ])
                      ])
