import Foundation

public struct TuistTomlConfig: Equatable, Sendable, Decodable {
    public let project: String
    public let url: URL?

    public init(
        project: String,
        url: URL? = nil
    ) {
        self.project = project
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decode(String.self, forKey: .project)
        if let urlString = try container.decodeIfPresent(String.self, forKey: .url) {
            guard let parsed = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .url,
                    in: container,
                    debugDescription: "Invalid URL: \(urlString)"
                )
            }
            url = parsed
        } else {
            url = nil
        }
    }
}
