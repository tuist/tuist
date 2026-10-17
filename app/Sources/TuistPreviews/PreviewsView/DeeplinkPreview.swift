import Foundation
import TuistServer

public struct PreviewDestination: Hashable {
    public let preview: ServerPreview
    public let fullHandle: String

    public init(preview: ServerPreview, fullHandle: String) {
        self.preview = preview
        self.fullHandle = fullHandle
    }
}

public struct DeeplinkPreview: Hashable {
    public let previewId: String
    public let fullHandle: String

    public init?(url: URL) {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 4, components[2] == "previews" else { return nil }
        previewId = components[3]
        fullHandle = "\(components[0])/\(components[1])"
    }
}
