import Foundation
import TuistConfig

struct TuistTomlConfig: Equatable, Sendable, Decodable {
    struct Network: Equatable, Sendable, Decodable {
        let proxy: Bool?
        let caCertificate: String?

        init(proxy: Bool? = nil, caCertificate: String? = nil) {
            self.proxy = proxy
            self.caCertificate = caCertificate
        }

        private enum CodingKeys: String, CodingKey {
            case proxy
            case caCertificate = "ca_certificate"
        }
    }

    /// `[test_insights.coverage]`, read by projects whose only configuration is this file (Cargo).
    struct TestInsights: Equatable, Sendable, Decodable {
        struct Coverage: Equatable, Sendable, Decodable {
            let upload: Bool?
        }

        let coverage: Coverage?
    }

    let project: String?
    let url: URL?
    let network: Network?
    let testInsights: TestInsights?

    init(
        project: String? = nil,
        url: URL? = nil,
        network: Network? = nil,
        testInsights: TestInsights? = nil
    ) {
        self.project = project
        self.url = url
        self.network = network
        self.testInsights = testInsights
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case url
        case network
        case testInsights = "test_insights"
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
        testInsights = try container.decodeIfPresent(TestInsights.self, forKey: .testInsights)
    }
}
