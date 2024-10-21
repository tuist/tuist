import Foundation

/// Server command event
public struct ServerCommandEvent: Codable {
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

    public struct Artifact: Equatable {
        let type: ArtifactType
        let name: String?

        init(
            type: ArtifactType,
            name: String? = nil
        ) {
            self.type = type
            self.name = name
        }

        enum ArtifactType {
            case resultBundle, invocationRecord, resultBundleObject
        }
    }
}

extension ServerCommandEvent {
    init(_ commandEvent: Components.Schemas.CommandEvent) {
        id = Int(commandEvent.id)
        name = commandEvent.name
        url = URL(string: commandEvent.url)!
    }
}

extension Components.Schemas.CommandEventArtifact {
    init(_ artifact: ServerCommandEvent.Artifact) {
        self = .init(name: artifact.name, _type: .init(artifact.type))
    }
}

extension Components.Schemas.CommandEventArtifact._typePayload {
    init(_ type: ServerCommandEvent.Artifact.ArtifactType) {
        switch type {
        case .resultBundle:
            self = .result_bundle
        case .invocationRecord:
            self = .invocation_record
        case .resultBundleObject:
            self = .result_bundle_object
        }
    }
}

#if MOCKING
    extension ServerCommandEvent {
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
