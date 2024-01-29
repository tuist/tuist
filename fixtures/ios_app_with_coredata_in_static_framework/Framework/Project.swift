import ProjectDescription

let project = Project(
    name: "Framework",
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.framework",
            infoPlist: .default,
            sources: ["Sources/**"],
            coreDataModels: [
                .coreDataModel("CoreData/Users.xcdatamodeld"),
            ]
        ),
    ]
)
