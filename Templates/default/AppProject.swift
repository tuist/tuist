import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let appProjectContent = Content {
    let name = try getAttribute(for: "name")
    // TODO: Handle error
    guard let platform = Platform(rawValue: try getAttribute(for: "platform")) else { fatalError() }
    return """
    import ProjectDescription
    import ProjectDescriptionHelpers

    let project = Project.app(name: "\(name)", platform: .\(platform.caseValue), dependencies: [
    .project(target: "\(name)Kit", path: .relativeToManifest("../\(platform.caseValue)Kit"))
    ])
    """
}
