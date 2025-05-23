import Foundation
import ProjectDescription

let workspace = Workspace(
    name: try {
        let configData = try Data(contentsOf: URL(fileURLWithPath: "config.json"))
        let config = try JSONDecoder().decode([String: String].self, from: configData)
        return config["workspace_name"]!
    }(),
    projects: ["App"]
)
