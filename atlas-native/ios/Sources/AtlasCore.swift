import AtlasCoreFFI
import Foundation

struct AtlasSection: Identifiable {
    let id: Int32
    let title: String
    let description: String
    let url: URL
    let screen: String
}

enum AtlasCore {
    static func sections() -> [AtlasSection] {
        (0..<atlas_section_count()).compactMap { index in
            guard
                let title = field(section: index, id: 0),
                let description = field(section: index, id: 1),
                let destination = field(section: index, id: 2),
                let screen = field(section: index, id: 3),
                let url = URL(string: destination),
                url.scheme == "https", url.host == "atlas.tuist.dev"
            else { return nil }
            return AtlasSection(id: index, title: title, description: description, url: url, screen: screen)
        }
    }

    static func field(section: Int32, id: Int32) -> String? {
        guard let pointer = atlas_section_field(section, id) else { return nil }
        return String(validatingCString: pointer)
    }
}
