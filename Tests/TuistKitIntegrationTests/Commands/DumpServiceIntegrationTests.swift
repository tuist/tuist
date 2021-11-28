import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoader
@testable import TuistSupportTesting

final class DumpServiceTests: TuistTestCase {
    private var subject: DumpService!

    override func setUp() {
        super.setUp()
        subject = DumpService()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_prints_the_manifest_when_project_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let project = Project(
            name: "tuist",
            organizationName: "tuist",
            settings: nil,
            targets: [],
            resourceSynthesizers: []
        )
        """
        try config.write(
            toFile: tmpDir.appending(component: "Project.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .project)
        let expected = """
        {
          "additionalFiles": [

          ],
          "name": "tuist",
          "options": [

          ],
          "organizationName": "tuist",
          "packages": [

          ],
          "resourceSynthesizers": [

          ],
          "schemes": [

          ],
          "targets": [

          ]
        }

        """

        XCTAssertPrinterOutputContains(expected)
    }

    func test_prints_the_manifest_when_workspace_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let workspace = Workspace(
            name: "tuist",
            projects: [],
            schemes: [],
            fileHeaderTemplate: nil,
            additionalFiles: []
        )
        """
        try config.write(
            toFile: tmpDir.appending(component: "Workspace.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .workspace)
        let expected = """
        {
          "additionalFiles": [

          ],
          "name": "tuist",
          "projects": [

          ],
          "schemes": [

          ]
        }

        """

        XCTAssertPrinterOutputContains(expected)
    }

    func test_prints_the_manifest_when_config_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let config = Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            swiftVersion: nil,
            plugins: [],
            generationOptions: []
        )
        """
        try fileHandler.createFolder(tmpDir.appending(component: "Tuist"))
        try config.write(
            toFile: tmpDir.appending(components: "Tuist", "Config.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .config)
        let expected = """
        {
          "compatibleXcodeVersions": {
            "type": "all"
          },
          "generationOptions": [

          ],
          "plugins": [

          ]
        }

        """

        XCTAssertPrinterOutputContains(expected)
    }

    func test_prints_the_manifest_when_template_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let template = Template(
            description: "tuist",
            attributes: [],
            items: []
        )
        """
        try config.write(
            toFile: tmpDir.appending(component: "\(tmpDir.basenameWithoutExt).swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .template)
        let expected = """
        {
          "attributes": [

          ],
          "description": "tuist",
          "items": [

          ]
        }

        """

        XCTAssertPrinterOutputContains(expected)
    }

    func test_prints_the_manifest_when_plugin_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let plugin = Plugin(
            name: "tuist"
        )
        """
        try config.write(
            toFile: tmpDir.appending(component: "Plugin.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .plugin)
        let expected = """
        {
          "name": "tuist"
        }

        """

        XCTAssertPrinterOutputContains(expected)
    }

    func test_prints_the_manifest_when_dependencies_manifest() throws {
        let tmpDir = try temporaryPath()
        let config = """
        import ProjectDescription

        let dependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: nil,
            platforms: []
        )
        """
        try fileHandler.createFolder(tmpDir.appending(component: "Tuist"))
        try config.write(
            toFile: tmpDir.appending(components: "Tuist", "Dependencies.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try subject.run(path: tmpDir.pathString, manifest: .dependencies)
        let expected = """
        {
          "platforms": [

          ]
        }

        """

        XCTAssertPrinterOutputContains(expected)
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

    // MARK: - Helpers

    private func assertLoadingRaisesWhenManifestNotFound(manifest: DumpableManifest) throws {
        try fileHandler.inTemporaryDirectory { tmpDir in
            var expectedDirectory = tmpDir
            if manifest == .config {
                expectedDirectory = expectedDirectory.appending(component: Constants.tuistDirectoryName)
                if !fileHandler.exists(expectedDirectory) {
                    try fileHandler.createFolder(expectedDirectory)
                }
            }
            XCTAssertThrowsSpecific(
                try subject.run(path: tmpDir.pathString, manifest: manifest),
                ManifestLoaderError.manifestNotFound(manifest.manifest, expectedDirectory)
            )
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
