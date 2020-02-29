import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let customContent = Content {
    let name = try getAttribute(for: "name")
    guard let platform = Platform(rawValue: try getAttribute(for: "platform")) else { fatalError() }
    return """
    This was generated with scaffold with name: \(name) and platform: \(platform.caseValue)
    
    """
}
