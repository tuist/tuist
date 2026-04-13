import Foundation
import TuistConfig

struct TuistTomlConfig: Equatable, Sendable, Decodable {
    let project: String
    let url: URL?
    let proxy: TuistTomlProxy?

    init(
        project: String,
        url: URL? = nil,
        proxy: TuistTomlProxy? = nil
    ) {
        self.project = project
        self.url = url
        self.proxy = proxy
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case url
        case proxy
    }

    init(from decoder: Decoder) throws {
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
        proxy = try container.decodeIfPresent(TuistTomlProxy.self, forKey: .proxy)
    }
}

/// Raw `[proxy]` table read from `tuist.toml`. Exactly one of `url` or
/// `environment_variable` must be set.
///
/// ```toml
/// [proxy]
/// url = "http://proxy.corp:8080"
///
/// # or
/// [proxy]
/// environment_variable = "HTTPS_PROXY"
/// ```
struct TuistTomlProxy: Equatable, Sendable, Decodable {
    let url: URL?
    let environmentVariable: String?

    init(url: URL? = nil, environmentVariable: String? = nil) {
        self.url = url
        self.environmentVariable = environmentVariable
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case environmentVariable = "environment_variable"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let urlString = try container.decodeIfPresent(String.self, forKey: .url) {
            guard let parsed = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .url,
                    in: container,
                    debugDescription: "Invalid proxy URL: \(urlString)"
                )
            }
            url = parsed
        } else {
            url = nil
        }

        environmentVariable = try container.decodeIfPresent(String.self, forKey: .environmentVariable)

        if url != nil, environmentVariable != nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "[proxy] accepts either `url` or `environment_variable`, not both."
                )
            )
        }
        if url == nil, environmentVariable == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "[proxy] must set either `url` or `environment_variable`."
                )
            )
        }
    }

    /// Translates this TOML proxy table into the runtime `TuistConfig.Tuist.Proxy`.
    func toTuistConfigProxy() -> (proxy: TuistConfig.Tuist.Proxy, isSet: Bool) {
        if let url {
            return (.url(url), true)
        }
        if let environmentVariable {
            return (.environmentVariable(environmentVariable), true)
        }
        return (.none, false)
    }
}
