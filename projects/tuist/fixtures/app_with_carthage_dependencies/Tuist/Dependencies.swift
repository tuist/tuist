import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "Alamofire/Alamofire", requirement: .exact("5.4.4")),
        .github(path: "Quick/Nimble", requirement: .exact("9.2.1")),
    ],
    platforms: [.iOS]
)
