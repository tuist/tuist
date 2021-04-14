import Foundation
import TSCBasic
import TuistSupport

final class LocalService {
    private let versionController: VersionsControlling

    init(versionController: VersionsControlling = VersionsController()) {
        self.versionController = versionController
    }

    func run(version: String?) throws {
        if let version = version {
            try createVersionFile(version: version)
        } else {
            try printLocalVersions()
        }
    }

    // MARK: - Helpers

    private func printLocalVersions() throws {
        logger.notice("The following versions are available in the local environment:", metadata: .section)
        let versions = versionController.semverVersions()
        let output = versions.sorted().reversed().map { "- \($0)" }.joined(separator: "\n")
        logger.notice("\(output)")
    }

    private func createVersionFile(version: String) throws {
        let currentPath = FileHandler.shared.currentPath
        logger.notice("Generating \(Constants.versionFileName) file with version \(version)", metadata: .section)
        let tuistVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(
            to: URL(fileURLWithPath: tuistVersionPath.pathString),
            atomically: true,
            encoding: .utf8
        )
        logger.notice("File generated at path \(tuistVersionPath.pathString)", metadata: .success)
    }
}
