import ProjectDescription

let dependencies = Dependencies(
    carthageDependencies: .init(
        dependencies: [
            .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4"))
        ],
        options: .init(
            platforms: [.iOS, .macOS],
            useXCFrameworks: true
        )
    )
)
