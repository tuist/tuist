import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ScaffoldAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_templates"))
    func ios_app_with_templates_custom() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom", "--name", "TemplateProject", "--path", fixturePath.pathString]
        )
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift"))
                == "// this is test TemplateProject content"
        )
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift"))
                == """
                // Generated file with platform: ios and name: TemplateProject

                """
        )
    }

    @Test(.withFixture("generated_ios_app_with_templates"))
    func ios_app_with_templates_custom_using_filters() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_filters",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom_using_filters", "--name", "TemplateProject", "--path", fixturePath.pathString]
        )
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift"))
                == "// this is test TemplateProject content"
        )
    }

    @Test(.withFixture("generated_ios_app_with_templates"))
    func ios_app_with_templates_custom_using_copy_folder() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_copy_folder",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom_using_copy_folder", "--name", "TemplateProject", "--path", fixturePath.pathString]
        )
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift"))
                == """
                // Generated file with platform: ios and name: TemplateProject

                """
        )
        #expect(
            try FileHandler.shared.readTextFile(
                templateProjectDirectory.appending(components: ["sourceFolder", "file1.txt"])
            )
                == """
                Content of file 1

                """
        )
        #expect(
            try FileHandler.shared.readTextFile(
                templateProjectDirectory.appending(components: ["sourceFolder", "subFolder", "file2.txt"])
            )
                == """
                Content of file 2

                """
        )
    }

    @Test(.withFixture("generated_app_with_plugins"))
    func app_with_plugins_local_plugin() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom",
            "--name",
            "PluginTemplate",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom", "--name", "PluginTemplate", "--path", fixturePath.pathString]
        )
        let pluginTemplateDirectory = fixturePath.appending(component: "PluginTemplate")
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "custom.swift"))
                == "// this is test PluginTemplate content"
        )
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "generated.swift"))
                == """
                // Generated file with platform: ios and name: PluginTemplate

                """
        )
    }

    @Test(.withFixture("generated_app_with_plugins"))
    func app_with_plugins_remote_plugin() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_two",
            "--name",
            "PluginTemplate",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom_two", "--name", "PluginTemplate", "--path", fixturePath.pathString]
        )
        let pluginTemplateDirectory = fixturePath.appending(component: "PluginTemplate")
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "custom.swift"))
                == "// this is test PluginTemplate content"
        )
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "generated.swift"))
                == """
                // Generated file with platform: ios and name: PluginTemplate

                """
        )
    }

    @Test(.withFixture("generated_ios_app_with_templates"))
    func ios_app_with_templates_custom_using_attribute() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "custom_using_attribute",
            "--name",
            "TemplateProject",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(
            ScaffoldCommand.self,
            ["custom_using_attribute", "--name", "TemplateProject", "--path", fixturePath.pathString]
        )
        let templateProjectDirectory = fixturePath.appending(component: "TemplateProject")
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "custom.swift"))
                == "// this is test TemplateProject content"
        )
        #expect(
            try FileHandler.shared.readTextFile(templateProjectDirectory.appending(component: "generated.swift"))
                == """
                // Generated file name: TemplateProject
                // Generated file with supporting platforms
                // iOS

                """
        )
    }

    @Test(.withFixture("generated_ios_app_with_plugins_and_templates"))
    func ios_app_with_local_template_and_project_description_helpers_plugin() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "example",
            "--name",
            "PluginAndTemplate",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(ScaffoldCommand.self, ["example", "--path", fixturePath.pathString])
        let pluginTemplateDirectory = fixturePath.appending(component: "Sources")
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "LocalTemplateTest.swift"))
                == "// Generated file named LocalPlugin from local template"
        )
    }

    @Test(.withFixture("generated_ios_app_with_plugins_and_templates"))
    func ios_app_with_plugin_template_and_project_description_helpers_plugin() async throws {
        defer { resetScaffoldOptions() }
        let fixturePath = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
        try await ScaffoldCommand.preprocess([
            "scaffold",
            "plugin",
            "--name",
            "PluginAndTemplate",
            "--path",
            fixturePath.pathString,
        ])
        try await TuistTest.run(ScaffoldCommand.self, ["plugin", "--path", fixturePath.pathString])
        let pluginTemplateDirectory = fixturePath.appending(component: "Sources")
        #expect(
            try FileHandler.shared.readTextFile(pluginTemplateDirectory.appending(component: "PluginTemplateTest.swift"))
                == "// Generated file named LocalPlugin from plugin"
        )
    }
}

private func resetScaffoldOptions() {
    ScaffoldCommand.requiredTemplateOptions = []
    ScaffoldCommand.optionalTemplateOptions = []
}
