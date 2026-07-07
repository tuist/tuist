import Foundation
import Gzip
import XCLogParser

enum SLFLogLoader {
    static func load(from url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            let unzipped = try data.gunzipped()
            return String(decoding: unzipped, as: UTF8.self)
        } catch {
            throw LogError.invalidFile(url.path)
        }
    }
}
