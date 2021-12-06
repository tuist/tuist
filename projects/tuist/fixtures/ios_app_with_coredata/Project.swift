import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            coreDataModels: [
                CoreDataModel("CoreData/Users.xcdatamodeld", currentVersion: "1"),
                CoreDataModel("CoreData/UsersAutoDetect.xcdatamodeld"),
                CoreDataModel("CoreData/Unversioned.xcdatamodeld"),
            ]
        ),
    ]
)
