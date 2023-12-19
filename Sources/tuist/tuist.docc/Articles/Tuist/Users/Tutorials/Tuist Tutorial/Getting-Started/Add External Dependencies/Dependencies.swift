import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    ),
    platforms: [.iOS],
)
