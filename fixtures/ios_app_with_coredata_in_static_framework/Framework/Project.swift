import ProjectDescription

let project = Project(
    name: "Framework",
    targets: [
        Target(
            name: "Framework",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.framework",
            infoPlist: .default,
            sources: ["Sources/**"],
            coreDataModels: [
                CoreDataModel("CoreData/Users.xcdatamodeld"),
            ]
        ),
    ]
)
