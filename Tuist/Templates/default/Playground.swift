import Foundation
import ProjectDescription
import ProjectDescriptionHelpers

let xcplaygroundContent = Content {
    let platform = try Platform.getFromAttributes()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <playground version='5.0' target-platform='\(platform.rawValue.lowercased())'>
    <timeline fileName='timeline.xctimeline'/>
    </playground>
    """
}
