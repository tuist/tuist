import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .git(path: "https://github.com/Alamofire/Alamofire", requirement: .exact("5.0.4")),
        .git(path: "https://github.com/Swinject/Swinject", requirement: .exact("2.7.1")),
    ],
    swiftPackageManager: [
        .package(url: "https://github.com/SnapKit/SnapKit.git", .upToNextMajor(from: "5.0.1")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .exact("6.1.0")),
    ],
    platforms: [.iOS]
)
