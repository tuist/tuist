import ProjectDescription

let project = Project(name: "MyFramework",
                      targets: [
                        Target(name: "MyFramework",
                             platform: .iOS,
                             product: .staticFramework,
                             bundleId: "io.tuist.framework",
                             infoPlist: .default,
                             sources: ["Sources/**"],
                             coreDataModels: [
                               CoreDataModel("CoreData/Users.xcdatamodeld", currentVersion: "1")
                             ])
                      ])
