import ProjectDescription

let dependencies = Dependencies(
    carthage: .carthage(
        [
            .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4"))
        ],
        options: [.useXCFrameworks, .noUseBinaries]
    ),
    swiftPackageManager: .swiftPackageManager(
        [
            .package(url: "https://github.com/SnapKit/SnapKit.git", .upToNextMajor(from: "5.0.1"))
        ]
    ),
    platforms: [.iOS]
)
