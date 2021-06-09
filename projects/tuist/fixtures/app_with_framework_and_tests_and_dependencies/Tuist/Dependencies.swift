import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "ReactiveX/RxSwift", requirement: .exact("5.1.2")),
    ],
    swiftPackageManager: [
        .package(url: "https://github.com/SnapKit/SnapKit.git", .upToNextMajor(from: "5.0.1"))
    ],
    platforms: [.iOS]
)
