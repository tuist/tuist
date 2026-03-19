import Mockable
import Path
import XcodeGraph

@Mockable
protocol InspectBundlePathResolving {
    func resolve(
        bundle: String,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?
    ) async throws -> AbsolutePath
}
