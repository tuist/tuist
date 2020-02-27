import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let appProjectContent = Content {
    let name = try getAttribute(for: "name")
    let platform = try Platform.getFromAttributes()
    return """
    import ProjectDescription
    import ProjectDescriptionHelpers

    let project = Project.app(name: "\(name)", platform: .\(platform.caseValue), dependencies: [
    .project(target: "\(name)Kit", path: .relativeToManifest("../\(platform.caseValue)Kit"))
    ])
    """
}
