import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "Alamofire/Alamofire", requirement: .exact("5.8.0")),
        .github(path: "Quick/Nimble", requirement: .exact("12.0.0")),
    ],
    platforms: [.iOS]
)
