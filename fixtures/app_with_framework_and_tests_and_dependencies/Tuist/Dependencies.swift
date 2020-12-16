import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .init(name: "Alamofire/Alamofire", requirement: .exact("5.0.4"), platforms: [.macOS]),
    ]
)
