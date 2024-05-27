import Foundation

/// Cloud command event
public struct CloudCommandEvent: Codable {
    public let id: Int
    public let name: String
    public let url: URL

    public init(
        id: Int,
        name: String,
        url: URL
    ) {
        self.id = id
        self.name = name
        self.url = url
    }
}

extension CloudCommandEvent {
    init(_ commandEvent: Components.Schemas.CommandEvent) {
        id = Int(commandEvent.id)
        name = commandEvent.name
        url = URL(string: commandEvent.url)!
    }
}

#if MOCKING
    extension CloudCommandEvent {
        public static func test(
            id: Int = 0,
            name: String = "generate",
            url: URL = URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
        ) -> Self {
            .init(
                id: id,
                name: name,
                url: url
            )
        }
    }
#endif
