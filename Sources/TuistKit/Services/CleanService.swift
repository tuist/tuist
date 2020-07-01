import Foundation
import TuistSupport

final class CleanService {
    func run() throws {
        let cachePath = Environment.shared.cacheDirectory
        try FileHandler.shared.delete(cachePath)
        logger.info("Successfully cleaned artefacts at path \(cachePath.pathString)", metadata: .success)
    }
}
