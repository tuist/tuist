import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(),
    platforms: [.iOS],
    productTypes: [
        "Alamofire": .framework, // default is .staticFramework
    ]
)
