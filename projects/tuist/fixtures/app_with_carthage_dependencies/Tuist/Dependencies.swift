import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "Alamofire/Alamofire", requirement: .exact("5.4.3")),
        .github(path: "Quick/Nimble", requirement: .exact("9.2.0")),
    ],
    platforms: [.iOS]
)
