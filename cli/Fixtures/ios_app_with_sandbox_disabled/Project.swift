import Foundation
import ProjectDescription

let project = {
    // This will crash if the sandbox is enabled
    try! String(contentsOfFile: "/etc/hosts", encoding: .utf8)

    return Project(
        name: "App",
        targets: [
            .target(
                name: "App",
                destinations: .iOS,
                product: .app,
                bundleId: "dev.tuist.App",
                sources: ["App/Sources/**"]
            ),
        ]
    )
}()
