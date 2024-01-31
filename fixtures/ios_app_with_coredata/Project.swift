import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            coreDataModels: [
                .coreDataModel("CoreData/Users.xcdatamodeld", currentVersion: "1"),
                .coreDataModel("CoreData/UsersAutoDetect.xcdatamodeld"),
                .coreDataModel("CoreData/Unversioned.xcdatamodeld"),
            ]
        ),
    ]
)
