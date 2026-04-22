import Foundation
import TuistConfig

struct TuistTomlConfig: Equatable, Sendable, Decodable {
    struct HTTP: Equatable, Sendable, Decodable {
        let proxy: Bool?

        init(proxy: Bool? = nil) {
            self.proxy = proxy
        }
    }

    let project: String?
    let url: URL?
    let http: HTTP?

    init(
        project: String? = nil,
        url: URL? = nil,
        http: HTTP? = nil
    ) {
        self.project = project
        self.url = url
        self.http = http
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case url
        case http
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
        http = try container.decodeIfPresent(HTTP.self, forKey: .http)
    }
}
