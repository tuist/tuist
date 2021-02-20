import ProjectDescription

let dependencies = Dependencies(
    carthage: .carthage(
        [
            .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4"))
        ],
        platforms: [.iOS, .macOS],
        useXCFrameworks: true
    )
)
