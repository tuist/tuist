import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let kitFrameworkProjectContent = Content {
    let name = try getAttribute(for: "name")
    let platform = try Platform.getFromAttributes()
    return """
    import ProjectDescription
    import ProjectDescriptionHelpers

    let project = Project.framework(name: "\(name)Kit", platform: .\(platform.caseValue), dependencies: [
        .project(target: "\(name)Support", path: .relativeToManifest("../\(platform.caseValue)Support"))
    ])
    """
}
