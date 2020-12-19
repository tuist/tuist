import ProjectDescription

let dependencies = Dependencies([
    .carthage(name: "Alamofire/Alamofire", requirement: .exact("5.0.4"), platforms: [.macOS])
])
