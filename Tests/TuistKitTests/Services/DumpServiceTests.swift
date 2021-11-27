import Foundation
import TSCBasic
import TuistLoader
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class DumpServiceTests: TuistUnitTestCase {
    var errorHandler: MockErrorHandler!
    var subject: DumpService!
    var manifestLoading: ManifestLoading!

    override func setUp() {
        super.setUp()
        errorHandler = MockErrorHandler()
        manifestLoading = ManifestLoader()
        subject = DumpService(manifestLoader: manifestLoading)
    }

    override func tearDown() {
        errorHandler = nil
        manifestLoading = nil
        subject = nil
        super.tearDown()
    }

    private func assertLoadingRaisesWhenManifestNotFound(manifest: DumpableManifest) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        var expectedDirectory = tmpDir.path
        if manifest == .config {
            expectedDirectory = expectedDirectory.appending(component: Constants.tuistDirectoryName)
            try FileHandler.shared.createFolder(expectedDirectory)
        }
        XCTAssertThrowsSpecific(
            try subject.run(path: tmpDir.path.pathString, manifest: manifest),
            ManifestLoaderError.manifestNotFound(manifest.manifest, expectedDirectory)
        )
    }

    func test_run_throws_when_project_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .project)
    }

    func test_run_throws_when_workspace_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .workspace)
    }

    func test_run_throws_when_config_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .config)
    }

    func test_run_throws_when_template_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .template)
    }

    func test_run_throws_when_dependencies_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .dependencies)
    }

    func test_run_throws_when_plugin_and_file_doesnt_exist() throws {
        try assertLoadingRaisesWhenManifestNotFound(manifest: .plugin)
    }

    func test_run_throws_when_the_manifest_loading_fails() throws {
        for manifest in DumpableManifest.allCases {
            let tmpDir = try temporaryPath()
            try "invalid config".write(
                toFile: tmpDir.appending(component: manifest.manifest.fileName(tmpDir)).pathString,
                atomically: true,
                encoding: .utf8
            )
            XCTAssertThrowsError(try subject.run(path: tmpDir.pathString, manifest: manifest))
        }
    }
}

extension DumpableManifest {
    var manifest: Manifest {
        switch self {
        case .project:
            return .project
        case .workspace:
            return .workspace
        case .config:
            return .config
        case .template:
            return .template
        case .dependencies:
            return .dependencies
        case .plugin:
            return .plugin
        }
    }
}
