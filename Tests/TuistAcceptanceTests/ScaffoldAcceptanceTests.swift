import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class ScaffoldAcceptanceTests: TuistAcceptanceTestCase {
    override func tearDown() {
        ScaffoldCommand.requiredTemplateOptions = []
        ScaffoldCommand.optionalTemplateOptions = []
        super.tearDown()
    }

    func test_ios_app_with_templates_custom() async throws {
        try setUpFixture(.iosAppWithTemplates)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await run(ScaffoldCommand.self, "custom", "--name", "TemplateProject")
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift")),
            "// this is test TemplateProject content"
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift")),
            """
            // Generated file with platform: ios and name: TemplateProject

            """
        )
    }

    func test_ios_app_with_templates_custom_using_filters() async throws {
        try setUpFixture(.iosAppWithTemplates)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_filters",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await run(ScaffoldCommand.self, "custom_using_filters", "--name", "TemplateProject")
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift")),
            "// this is test TemplateProject content"
        )
    }

    func test_ios_app_with_templates_custom_using_copy_folder() async throws {
        try setUpFixture(.iosAppWithTemplates)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_copy_folder",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await run(ScaffoldCommand.self, "custom_using_copy_folder", "--name", "TemplateProject")
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift")),
            """
            // Generated file with platform: ios and name: TemplateProject

            """
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(
                templateProjectDirectory.appending(components: ["sourceFolder", "file1.txt"])
            ),
            """
            Content of file 1

            """
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(
                templateProjectDirectory.appending(components: ["sourceFolder", "subFolder", "file2.txt"])
            ),
            """
            Content of file 2

            """
        )
    }

    func test_app_with_plugins_local_plugin() async throws {
        try setUpFixture(.appWithPlugins)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess(["scaffold", "custom", "--name", "PluginTemplate", "--path", fixturePath.pathString])
        try await run(ScaffoldCommand.self, "custom", "--name", "PluginTemplate")
        let pluginTemplateDirectory = fixturePath.appending(component: "PluginTemplate")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "custom.swift")),
            "// this is test PluginTemplate content"
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "generated.swift")),
            """
            // Generated file with platform: ios and name: PluginTemplate

            """
        )
    }

    func test_app_with_plugins_remote_plugin() async throws {
        try setUpFixture(.appWithPlugins)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_two",
            "--name",
            "PluginTemplate",
            "--path",
            fixturePath.pathString,
        ])
        try await run(ScaffoldCommand.self, "custom_two", "--name", "PluginTemplate")
        let pluginTemplateDirectory = fixturePath.appending(component: "PluginTemplate")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "custom.swift")),
            "// this is test PluginTemplate content"
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "generated.swift")),
            """
            // Generated file with platform: ios and name: PluginTemplate

            """
        )
    }

    func test_ios_app_with_templates_custom_using_attribute() async throws {
        try setUpFixture(.iosAppWithTemplates)
        try await run(InstallCommand.self)
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_attribute",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await run(ScaffoldCommand.self, "custom_using_attribute", "--name", "TemplateProject")
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift")),
            "// this is test TemplateProject content"
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift")),
            """
            // Generated file name: TemplateProject
            // Generated file with supporting platforms
            // iOS

            """
        )
    }
}
