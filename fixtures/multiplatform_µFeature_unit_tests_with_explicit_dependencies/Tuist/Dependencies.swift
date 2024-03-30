import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "Mocker": .framework,
        ]
    ),
    platforms: [.iOS, .watchOS]
)
