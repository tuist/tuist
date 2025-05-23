import Foundation
import ProjectDescription

let project = Project(
    name: try {
        let configData = try Data(contentsOf: URL(fileURLWithPath: "config.json"))
        let config = try JSONDecoder().decode([String: String].self, from: configData)
        return config["project_name"]!
    }(),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**"]
        ),
    ]
)
