import ProjectDescription

let dependencies = Dependencies([
    .carthage(origin: .github(path: "Alamofire/Alamofire"), requirement: .exact("5.0.4"), platforms: [.macOS])
])
