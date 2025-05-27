import Foundation
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["App/Sources/**"]
        ),
    ]
)

try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
