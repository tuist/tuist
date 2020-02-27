import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let supportFrameworkProjectContent = Content {
    let name = try getAttribute(for: "name")
    let platform = try Platform.getFromAttributes()
    return """
    import ProjectDescription
    import ProjectDescriptionHelpers

    let project = Project.framework(name: "\(name)Support", platform: .\(platform.caseValue), dependencies: [])
    """
}
