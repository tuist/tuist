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
            .package(url: "https://github.com/ReactiveX/RxSwift.git", .exact("5.1.1"))
        ]
    ),
    platforms: [.iOS]
)
