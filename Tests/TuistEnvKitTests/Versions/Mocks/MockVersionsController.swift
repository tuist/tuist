import Basic
import Foundation
import Utility
@testable import TuistEnvKit

final class MockVersionsController: VersionsControlling {
    fileprivate let tmpDir: TemporaryDirectory
    var path: AbsolutePath { return tmpDir.path }
    var pathCallCount: UInt = 0
    var pathStub: ((String) -> AbsolutePath)?
    var installCallCount: UInt = 0
    var installStub: ((String, Installation) throws -> Void)?
    var versionsCallCount: UInt = 0
    var versionsStub: [InstalledVersion] = []
    var semverVersionsCount: UInt = 0
    var semverVersionsStub: [Version] = []

    init() throws {
        tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        installStub = { version, installation in
            try installation(self.path.appending(component: version))
        }
        pathStub = { version in
            self.path.appending(component: version)
        }
    }

    func path(version: String) -> AbsolutePath {
        pathCallCount += 1
        return pathStub?(version) ?? AbsolutePath("/test")
    }

    func install(version: String, installation: Installation) throws {
        installCallCount += 1
        try installStub?(version, installation)
    }

    func versions() -> [InstalledVersion] {
        versionsCallCount += 1
        return versionsStub
    }

    func semverVersions() -> [Version] {
        semverVersionsCount += 1
        return semverVersionsStub
    }
}
