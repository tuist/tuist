import ProjectDescription

let dependencies = Dependencies(
    carthage: .carthage(
        [
            .git(path: "https://github.com/Alamofire/Alamofire", requirement: .exact("5.0.4")),
            .git(path: "https://github.com/Swinject/Swinject", requirement: .exact("2.7.1"))
        ],
        platforms: [.macOS]
    )
)
