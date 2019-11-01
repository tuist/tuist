import Foundation
import SPMUtility
import TuistSupport

enum ReleaseDecodeError: FatalError, Equatable {
    case invalidVersionFormat(String)

    var type: ErrorType {
        switch self {
        case .invalidVersionFormat:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .invalidVersionFormat(version):
            return "Invalid release version format: \(version). It should have a valid semver format: x.y.z."
        }
    }

    static func == (lhs: ReleaseDecodeError, rhs: ReleaseDecodeError) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidVersionFormat(lhsVersion), .invalidVersionFormat(rhsVersion)):
            return lhsVersion == rhsVersion
        }
    }
}

struct Release: Decodable {
    struct Asset: Decodable {
        let downloadURL: Foundation.URL
        let name: String

        enum CodingKeys: String, CodingKey {
            case downloadURL = "browser_download_url"
            case name
        }
    }

    // MARK: - Attributes

    let id: Int
    let version: Version
    let name: String?
    let body: String?
    let assets: [Asset]

    // MARK: - Init

    init(id: Int,
         version: Version,
         name: String?,
         body: String?,
         assets: [Asset]) {
        self.id = id
        self.version = version
        self.name = name
        self.body = body
        self.assets = assets
    }

    // MARK: - Decodable

    enum CodingKeys: String, CodingKey {
        case id
        case version = "tag_name"
        case name
        case body
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let versionString: String = try container.decode(String.self, forKey: .version)
        guard let version = Version(string: versionString) else { throw ReleaseDecodeError.invalidVersionFormat(versionString) }
        self.version = version
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assets = try container.decode([Asset].self, forKey: .assets)
    }
}
