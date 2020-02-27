import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let supportFrameworkProjectContent = Content {
    let name = try getAttribute(for: "name")
    // TODO: Handle error
    guard let platform = Platform(rawValue: try getAttribute(for: "platform")) else { fatalError() }
    return """
    import ProjectDescription
    import ProjectDescriptionHelpers

    let project = Project.framework(name: "\(name)Support", platform: .\(platform.caseValue), dependencies: [])
    """
}
