import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: ["CoreData/Users1_2.xcmappingmodel"],
            coreDataModels: [
                .coreDataModel("CoreData/Users.xcdatamodeld", currentVersion: "1"),
                .coreDataModel("CoreData/UsersAutoDetect.xcdatamodeld"),
                .coreDataModel("CoreData/Unversioned.xcdatamodeld"),
            ]
        ),
    ],
    resourceSynthesizers: .default + [.coreData()]
)
