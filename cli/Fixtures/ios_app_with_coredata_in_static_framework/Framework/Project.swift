import ProjectDescription

let project = Project(
    name: "Framework",
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.framework",
            infoPlist: .default,
            sources: ["Sources/**"],
            coreDataModels: [
                .coreDataModel("CoreData/Users.xcdatamodeld"),
            ]
        ),
    ]
)
