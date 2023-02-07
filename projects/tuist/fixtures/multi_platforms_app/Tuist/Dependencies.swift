import ProjectDescription

let dependencies = Dependencies(
    carthage: [],
    swiftPackageManager: .init(
        [
            .zipFoundation
        ],
        productTypes: [:],
        targetSettings: [:]
    ),
    platforms: [.macOS, .iOS, .tvOS, .watchOS]
)

extension Package {
    public static let zipFoundation = package(
        url: "https://github.com/weichsel/ZIPFoundation.git",
        .upToNextMajor(from: "0.9.14")
    )

    public static let quick = package(
        url: "https://github.com/Quick/Quick.git",
        .upToNextMajor(from: "5.0.1")
    )

    public static let nimble = package(
        url: "https://github.com/Quick/Nimble.git",
        .upToNextMajor(from: "10.0.0")
    )
}
