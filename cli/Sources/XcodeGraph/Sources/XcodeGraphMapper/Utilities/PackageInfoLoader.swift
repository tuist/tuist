import Foundation
import Mockable
import Path
import XcodeGraph

@Mockable
protocol PackageInfoLoading {
    func loadPackageInfo(at path: AbsolutePath) async throws -> PackageInfo
}

struct PackageInfoLoader: PackageInfoLoading {
    private let decoder = JSONDecoder()

    func loadPackageInfo(at path: AbsolutePath) async throws -> PackageInfo {
        let output = try await SubprocessRunner.capture(
            arguments: [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ]
        )

        let data = Data(output.utf8)

        return try decoder.decode(PackageInfo.self, from: data)
    }
}
