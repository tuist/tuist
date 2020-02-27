import Foundation
import TemplateDescription
import TemplateDescriptionHelpers

let xcplaygroundContent = Content {
    // TODO: Handle error
    guard let platform = Platform(rawValue: try getAttribute(for: "platform")) else { fatalError() }
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <playground version='5.0' target-platform='\(platform.rawValue.lowercased())'>
    <timeline fileName='timeline.xctimeline'/>
    </playground>
    """
}
