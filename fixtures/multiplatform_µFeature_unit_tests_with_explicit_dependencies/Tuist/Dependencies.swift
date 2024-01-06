import ProjectDescription
import ProjectDescriptionHelpers

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "Mocker": .framework,
        ],
        targetSettings: [
            "Mocker": .init().merging(["ENABLE_TESTING_SEARCH_PATHS": SettingValue(booleanLiteral: true)]),
        ]
    ),
    platforms: [.iOS, .watchOS]
)
