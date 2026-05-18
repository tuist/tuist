import Foundation
import TuistConfig

struct TuistTomlConfig: Equatable, Sendable, Decodable {
    struct Network: Equatable, Sendable, Decodable {
        let proxy: Bool?

        init(proxy: Bool? = nil) {
            self.proxy = proxy
        }
    }

    let project: String?
    let url: URL?
    let network: Network?

    init(
        project: String? = nil,
        url: URL? = nil,
        network: Network? = nil
    ) {
        self.project = project
        self.url = url
        self.network = network
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case url
        case network
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(String.self, forKey: .project)
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
        network = try container.decodeIfPresent(Network.self, forKey: .network)
    }
}
