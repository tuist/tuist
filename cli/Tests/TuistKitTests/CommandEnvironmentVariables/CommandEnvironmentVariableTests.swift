import ArgumentParser
import Difference
import Foundation
import Testing
import TSCUtility
@testable import TuistCore
@testable import TuistKit
@testable import TuistSupport
@testable import TuistTesting

struct CommandEnvironmentVariableTests {
    private var tuistVariables: [String: String] {
        get {
            return Environment.mocked?.variables ?? [:]
        }
        set {
            Environment.mocked?.variables = newValue
        }
    }

    private func setVariable(_ key: EnvKey, value: String) {
        Environment.mocked?.variables[key.rawValue] = value
    }

    @Test(.withMockedEnvironment()) func buildCommandUsesEnvVars() throws {
        setVariable(.buildOptionsScheme, value: "Scheme1")
        setVariable(.buildOptionsGenerate, value: "true")
        setVariable(.buildOptionsClean, value: "true")
        setVariable(.buildOptionsPath, value: "/path/to/project")
        setVariable(.buildOptionsDevice, value: "iPhone")
        setVariable(.buildOptionsPlatform, value: "ios")
        setVariable(.buildOptionsOS, value: "14.5.0")
        setVariable(.buildOptionsRosetta, value: "true")
        setVariable(.buildOptionsConfiguration, value: "Debug")
        setVariable(.buildOptionsOutputPath, value: "/path/to/output")
        setVariable(.buildOptionsDerivedDataPath, value: "/path/to/derivedData")
        setVariable(.buildOptionsGenerateOnly, value: "true")
        setVariable(.buildOptionsPassthroughXcodeBuildArguments, value: "clean,-configuration,Release")

        let buildCommandWithEnvVars = try BuildCommand.parse([])
        #expect(buildCommandWithEnvVars.buildOptions.scheme == "Scheme1")
        #expect(buildCommandWithEnvVars.buildOptions.generate == true)
        #expect(buildCommandWithEnvVars.buildOptions.clean == true)
        #expect(buildCommandWithEnvVars.buildOptions.path == "/path/to/project")
        #expect(buildCommandWithEnvVars.buildOptions.device == "iPhone")
        #expect(buildCommandWithEnvVars.buildOptions.platform == .iOS)
        #expect(buildCommandWithEnvVars.buildOptions.os == "14.5.0")
        #expect(buildCommandWithEnvVars.buildOptions.rosetta == true)
        #expect(buildCommandWithEnvVars.buildOptions.configuration == "Debug")
        #expect(buildCommandWithEnvVars.buildOptions.buildOutputPath == "/path/to/output")
        #expect(buildCommandWithEnvVars.buildOptions.derivedDataPath == "/path/to/derivedData")
        #expect(buildCommandWithEnvVars.buildOptions.generateOnly == true)
        #expect(
            buildCommandWithEnvVars.buildOptions.passthroughXcodeBuildArguments ==
                ["clean", "-configuration", "Release"]
        )

        let buildCommandWithArgs = try BuildCommand.parse([
            "Scheme2",
            "--generate",
            "--no-clean",
            "--path", "/new/path",
            "--device", "iPad",
            "--platform", "tvos",
            "--no-rosetta",
            "--configuration", "Release",
            "--build-output-path", "/new/output",
            "--derived-data-path", "/new/derivedData",
            "--no-generate-only",
            "--",
            "-configuration", "Debug",
        ])
        #expect(buildCommandWithArgs.buildOptions.scheme == "Scheme2")
        #expect(buildCommandWithArgs.buildOptions.generate == true)
        #expect(buildCommandWithArgs.buildOptions.clean == false)
        #expect(buildCommandWithArgs.buildOptions.path == "/new/path")
        #expect(buildCommandWithArgs.buildOptions.device == "iPad")
        #expect(buildCommandWithArgs.buildOptions.platform == .tvOS)
        #expect(buildCommandWithArgs.buildOptions.rosetta == false)
        #expect(buildCommandWithArgs.buildOptions.configuration == "Release")
        #expect(buildCommandWithArgs.buildOptions.buildOutputPath == "/new/output")
        #expect(buildCommandWithArgs.buildOptions.derivedDataPath == "/new/derivedData")
        #expect(buildCommandWithArgs.buildOptions.generateOnly == false)
        #expect(buildCommandWithArgs.buildOptions.passthroughXcodeBuildArguments == ["-configuration", "Debug"])
    }

    @Test(.withMockedEnvironment()) func cleanCommandUsesEnvVars() throws {
        setVariable(.cleanCleanCategories, value: "dependencies")
        setVariable(.cleanPath, value: "/path/to/clean")

        let cleanCommandWithEnvVars = try CleanCommand.parse([])
        #expect(cleanCommandWithEnvVars.cleanCategories == [TuistCleanCategory.dependencies])
        #expect(cleanCommandWithEnvVars.path == "/path/to/clean")

        let cleanCommandWithArgs = try CleanCommand.parse([
            "manifests",
            "--path", "/new/clean/path",
        ])
        #expect(cleanCommandWithArgs.cleanCategories == [TuistCleanCategory.global(.manifests)])
        #expect(cleanCommandWithArgs.path == "/new/clean/path")
    }

    @Test(.withMockedEnvironment()) func dumpCommandUsesEnvVars() throws {
        setVariable(.dumpPath, value: "/path/to/dump")
        setVariable(.dumpManifest, value: "Project")

        let dumpCommandWithEnvVars = try DumpCommand.parse([])
        #expect(dumpCommandWithEnvVars.path == "/path/to/dump")
        #expect(dumpCommandWithEnvVars.manifest == .project)

        let dumpCommandWithArgs = try DumpCommand.parse([
            "workspace",
            "--path", "/new/dump/path",
        ])
        #expect(dumpCommandWithArgs.path == "/new/dump/path")
        #expect(dumpCommandWithArgs.manifest == .workspace)
    }

    @Test(.withMockedEnvironment()) func editCommandUsesEnvVars() throws {
        setVariable(.editPath, value: "/path/to/edit")
        setVariable(.editPermanent, value: "true")
        setVariable(.editOnlyCurrentDirectory, value: "true")

        let editCommandWithEnvVars = try EditCommand.parse([])
        #expect(editCommandWithEnvVars.path == "/path/to/edit")
        #expect(editCommandWithEnvVars.permanent == true)
        #expect(editCommandWithEnvVars.onlyCurrentDirectory == true)

        let editCommandWithArgs = try EditCommand.parse([
            "--path", "/new/edit/path",
            "--no-permanent",
            "--no-only-current-directory",
        ])
        #expect(editCommandWithArgs.path == "/new/edit/path")
        #expect(editCommandWithArgs.permanent == false)
        #expect(editCommandWithArgs.onlyCurrentDirectory == false)
    }

    @Test(.withMockedEnvironment()) func generateCommandUsesEnvVars() throws {
        setVariable(.generatePath, value: "/path/to/generate")
        setVariable(.generateOpen, value: "false")
        setVariable(.generateBinaryCache, value: "false")
        setVariable(.generateCacheProfile, value: "development")

        let generateCommandWithEnvVars = try GenerateCommand.parse([])
        #expect(generateCommandWithEnvVars.path == "/path/to/generate")
        #expect(generateCommandWithEnvVars.open == false)
        #expect(generateCommandWithEnvVars.binaryCache == false)
        #expect(generateCommandWithEnvVars.cacheProfile == "development")

        let generateCommandWithArgs = try GenerateCommand.parse([
            "--path", "/new/generate/path",
            "--open",
            "--binary-cache",
            "--cache-profile", "all-possible",
        ])
        #expect(generateCommandWithArgs.path == "/new/generate/path")
        #expect(generateCommandWithArgs.open == true)
        #expect(generateCommandWithArgs.binaryCache == true)
        #expect(generateCommandWithArgs.cacheProfile == .allPossible)
    }

    @Test(.withMockedEnvironment()) func graphCommandUsesEnvVars() throws {
        setVariable(.graphSkipTestTargets, value: "true")
        setVariable(.graphSkipExternalDependencies, value: "true")
        setVariable(.graphPlatform, value: "ios")
        setVariable(.graphFormat, value: "svg")
        setVariable(.graphOpen, value: "false")
        setVariable(.graphLayoutAlgorithm, value: "circo")
        setVariable(.graphTargets, value: "Target1,Target2")
        setVariable(.graphPath, value: "/path/to/graph")
        setVariable(.graphOutputPath, value: "/path/to/output")

        let graphCommandWithEnvVars = try GraphCommand.parse([])
        #expect(graphCommandWithEnvVars.skipTestTargets == true)
        #expect(graphCommandWithEnvVars.skipExternalDependencies == true)
        #expect(graphCommandWithEnvVars.platform == .iOS)
        #expect(graphCommandWithEnvVars.format == .svg)
        #expect(graphCommandWithEnvVars.open == false)
        #expect(graphCommandWithEnvVars.layoutAlgorithm == .circo)
        #expect(graphCommandWithEnvVars.targets == ["Target1", "Target2"])
        #expect(graphCommandWithEnvVars.path == "/path/to/graph")
        #expect(graphCommandWithEnvVars.outputPath == "/path/to/output")

        let graphCommandWithArgs = try GraphCommand.parse([
            "--no-skip-test-targets",
            "--no-skip-external-dependencies",
            "--platform", "macos",
            "--format", "json",
            "--open",
            "--algorithm", "fdp",
            "Target3", "Target4",
            "--path", "/new/graph/path",
            "--output-path", "/new/graph/output",
        ])
        #expect(graphCommandWithArgs.skipTestTargets == false)
        #expect(graphCommandWithArgs.skipExternalDependencies == false)
        #expect(graphCommandWithArgs.platform == .macOS)
        #expect(graphCommandWithArgs.format == .json)
        #expect(graphCommandWithArgs.open == true)
        #expect(graphCommandWithArgs.layoutAlgorithm == .fdp)
        #expect(graphCommandWithArgs.targets == ["Target3", "Target4"])
        #expect(graphCommandWithArgs.path == "/new/graph/path")
        #expect(graphCommandWithArgs.outputPath == "/new/graph/output")
    }

    @Test(.withMockedEnvironment()) func installCommandUsesEnvVars() throws {
        setVariable(.installPath, value: "/path/to/install")
        setVariable(.installUpdate, value: "true")

        let installCommandWithEnvVars = try InstallCommand.parse([])
        #expect(installCommandWithEnvVars.path == "/path/to/install")
        #expect(installCommandWithEnvVars.update == true)

        let installCommandWithArgs = try InstallCommand.parse([
            "--path", "/new/install/path",
            "--no-update",
        ])
        #expect(installCommandWithArgs.path == "/new/install/path")
        #expect(installCommandWithArgs.update == false)
    }

    @Test(.withMockedEnvironment()) func listCommandUsesEnvVars() throws {
        setVariable(.scaffoldListJson, value: "true")
        setVariable(.scaffoldListPath, value: "/path/to/list")

        let listCommandWithEnvVars = try ListCommand.parse([])
        #expect(listCommandWithEnvVars.json == true)
        #expect(listCommandWithEnvVars.path == "/path/to/list")

        let listCommandWithArgs = try ListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        #expect(listCommandWithArgs.json == false)
        #expect(listCommandWithArgs.path == "/new/list/path")
    }

    @Test(.withMockedEnvironment()) func migrationCheckEmptyBuildSettingsCommandUsesEnvVars() throws {
        setVariable(.migrationCheckEmptySettingsXcodeprojPath, value: "/path/to/xcodeproj")
        setVariable(.migrationCheckEmptySettingsTarget, value: "MyTarget")

        let migrationCommandWithEnvVars = try MigrationCheckEmptyBuildSettingsCommand.parse([])
        #expect(migrationCommandWithEnvVars.xcodeprojPath == "/path/to/xcodeproj")
        #expect(migrationCommandWithEnvVars.target == "MyTarget")

        let migrationCommandWithArgs = try MigrationCheckEmptyBuildSettingsCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--target", "NewTarget",
        ])
        #expect(migrationCommandWithArgs.xcodeprojPath == "/new/xcodeproj/path")
        #expect(migrationCommandWithArgs.target == "NewTarget")
    }

    @Test(.withMockedEnvironment()) func migrationSettingsToXCConfigCommandUsesEnvVars() throws {
        setVariable(.migrationSettingsToXcconfigXcodeprojPath, value: "/path/to/xcodeproj")
        setVariable(.migrationSettingsToXcconfigXcconfigPath, value: "/path/to/xcconfig")
        setVariable(.migrationSettingsToXcconfigTarget, value: "MyTarget")

        let migrationCommandWithEnvVars = try MigrationSettingsToXCConfigCommand.parse([])
        #expect(migrationCommandWithEnvVars.xcodeprojPath == "/path/to/xcodeproj")
        #expect(migrationCommandWithEnvVars.xcconfigPath == "/path/to/xcconfig")
        #expect(migrationCommandWithEnvVars.target == "MyTarget")

        let migrationCommandWithArgs = try MigrationSettingsToXCConfigCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--xcconfig-path", "/new/xcconfig/path",
            "--target", "NewTarget",
        ])
        #expect(migrationCommandWithArgs.xcodeprojPath == "/new/xcodeproj/path")
        #expect(migrationCommandWithArgs.xcconfigPath == "/new/xcconfig/path")
        #expect(migrationCommandWithArgs.target == "NewTarget")
    }

    @Test(.withMockedEnvironment()) func migrationTargetsByDependenciesCommandUsesEnvVars() throws {
        setVariable(.migrationListTargetsXcodeprojPath, value: "/path/to/xcodeproj")

        let migrationCommandWithEnvVars = try MigrationTargetsByDependenciesCommand.parse([])
        #expect(migrationCommandWithEnvVars.xcodeprojPath == "/path/to/xcodeproj")

        let migrationCommandWithArgs = try MigrationTargetsByDependenciesCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
        ])
        #expect(migrationCommandWithArgs.xcodeprojPath == "/new/xcodeproj/path")
    }

    @Test(.withMockedEnvironment()) func pluginArchiveCommandUsesEnvVars() throws {
        setVariable(.pluginArchivePath, value: "/path/to/plugin")

        let pluginCommandWithEnvVars = try PluginArchiveCommand.parse([])
        #expect(pluginCommandWithEnvVars.path == "/path/to/plugin")

        let pluginCommandWithArgs = try PluginArchiveCommand.parse([
            "--path", "/new/plugin/path",
        ])
        #expect(pluginCommandWithArgs.path == "/new/plugin/path")
    }

    @Test(.withMockedEnvironment()) func pluginBuildCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginBuildBuildTests, value: "true")
        setVariable(.pluginBuildShowBinPath, value: "true")
        setVariable(.pluginBuildTargets, value: "Target1,Target2")
        setVariable(.pluginBuildProducts, value: "Product1,Product2")

        let pluginCommandWithEnvVars = try PluginBuildCommand.parse([])
        #expect(pluginCommandWithEnvVars.pluginOptions.path == "/path/to/plugin")
        #expect(pluginCommandWithEnvVars.pluginOptions.configuration == .debug)
        #expect(pluginCommandWithEnvVars.buildTests == true)
        #expect(pluginCommandWithEnvVars.showBinPath == true)
        #expect(pluginCommandWithEnvVars.targets == ["Target1", "Target2"])
        #expect(pluginCommandWithEnvVars.products == ["Product1", "Product2"])

        let pluginCommandWithArgs = try PluginBuildCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--no-show-bin-path",
            "--targets", "Target3", "--targets", "Target4",
            "--products", "Product3", "--products", "Product4",
        ])
        #expect(pluginCommandWithArgs.pluginOptions.path == "/new/plugin/path")
        #expect(pluginCommandWithArgs.pluginOptions.configuration == .release)
        #expect(pluginCommandWithArgs.buildTests == false)
        #expect(pluginCommandWithArgs.showBinPath == false)
        #expect(pluginCommandWithArgs.targets == ["Target3", "Target4"])
        #expect(pluginCommandWithArgs.products == ["Product3", "Product4"])
    }

    @Test(.withMockedEnvironment()) func pluginRunCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginRunBuildTests, value: "true")
        setVariable(.pluginRunSkipBuild, value: "true")
        setVariable(.pluginRunTask, value: "myTask")
        setVariable(.pluginRunArguments, value: "arg1,arg2,arg3")

        let pluginCommandWithEnvVars = try PluginRunCommand.parse([])
        #expect(pluginCommandWithEnvVars.pluginOptions.path == "/path/to/plugin")
        #expect(pluginCommandWithEnvVars.pluginOptions.configuration == .debug)
        #expect(pluginCommandWithEnvVars.buildTests == true)
        #expect(pluginCommandWithEnvVars.skipBuild == true)
        #expect(pluginCommandWithEnvVars.task == "myTask")
        #expect(pluginCommandWithEnvVars.arguments == ["arg1", "arg2", "arg3"])

        let pluginCommandWithArgs = try PluginRunCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--no-skip-build",
            "otherTask",
            "arg4", "arg5",
        ])
        #expect(pluginCommandWithArgs.pluginOptions.path == "/new/plugin/path")
        #expect(pluginCommandWithArgs.pluginOptions.configuration == .release)
        #expect(pluginCommandWithArgs.buildTests == false)
        #expect(pluginCommandWithArgs.skipBuild == false)
        #expect(pluginCommandWithArgs.task == "otherTask")
        #expect(pluginCommandWithArgs.arguments == ["arg4", "arg5"])
    }

    @Test(.withMockedEnvironment()) func pluginTestCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginTestBuildTests, value: "true")
        setVariable(.pluginTestTestProducts, value: "Product1,Product2")

        let pluginCommandWithEnvVars = try PluginTestCommand.parse([])
        #expect(pluginCommandWithEnvVars.pluginOptions.path == "/path/to/plugin")
        #expect(pluginCommandWithEnvVars.pluginOptions.configuration == .debug)
        #expect(pluginCommandWithEnvVars.buildTests == true)
        #expect(pluginCommandWithEnvVars.testProducts == ["Product1", "Product2"])

        let pluginCommandWithArgs = try PluginTestCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--test-products", "Product3", "--test-products", "Product4",
        ])
        #expect(pluginCommandWithArgs.pluginOptions.path == "/new/plugin/path")
        #expect(pluginCommandWithArgs.pluginOptions.configuration == .release)
        #expect(pluginCommandWithArgs.buildTests == false)
        #expect(pluginCommandWithArgs.testProducts == ["Product3", "Product4"])
    }

    @Test(.withMockedEnvironment()) func runCommandUsesEnvVars() throws {
        // Set environment variables for RunCommand
        setVariable(.runGenerate, value: "true")
        setVariable(.runClean, value: "true")
        setVariable(.runOS, value: "14.5")
        setVariable(.runScheme, value: "MyScheme")
        setVariable(.runArguments, value: "arg1,arg2,arg3")

        // Execute RunCommand without command line arguments
        let runCommandWithEnvVars = try RunCommand.parse([])
        #expect(runCommandWithEnvVars.generate == true)
        #expect(runCommandWithEnvVars.clean == true)
        #expect(runCommandWithEnvVars.os == "14.5")
        #expect(runCommandWithEnvVars.runnable == .scheme("MyScheme"))
        #expect(runCommandWithEnvVars.arguments == ["arg1", "arg2", "arg3"])

        // Execute RunCommand with command line arguments
        let runCommandWithArgs = try RunCommand.parse([
            "--no-generate",
            "--no-clean",
            "--path", "/new/run/path",
            "--configuration", "Release",
            "--device", "iPhone 12",
            "--os", "15.0",
            "--rosetta",
            "AnotherScheme",
            "arg4", "arg5",
        ])
        #expect(runCommandWithArgs.generate == false)
        #expect(runCommandWithArgs.clean == false)
        #expect(runCommandWithArgs.path == "/new/run/path")
        #expect(runCommandWithArgs.configuration == "Release")
        #expect(runCommandWithArgs.device == "iPhone 12")
        #expect(runCommandWithArgs.os == "15.0")
        #expect(runCommandWithArgs.rosetta == true)
        #expect(runCommandWithArgs.runnable == .scheme("AnotherScheme"))
        #expect(runCommandWithArgs.arguments == ["arg4", "arg5"])
    }

    @Test(.withMockedEnvironment()) func scaffoldCommandUsesEnvVars() throws {
        // Set environment variables for ScaffoldCommand
        setVariable(.scaffoldJson, value: "true")
        setVariable(.scaffoldPath, value: "/path/to/scaffold")
        setVariable(.scaffoldTemplate, value: "MyTemplate")

        // Execute ScaffoldCommand without command line arguments
        let scaffoldCommandWithEnvVars = try ScaffoldCommand.parse([])
        #expect(scaffoldCommandWithEnvVars.json == true)
        #expect(scaffoldCommandWithEnvVars.path == "/path/to/scaffold")
        #expect(scaffoldCommandWithEnvVars.template == "MyTemplate")

        // Execute ScaffoldCommand with command line arguments
        let scaffoldCommandWithArgs = try ScaffoldCommand.parse([
            "--no-json",
            "--path", "/new/scaffold/path",
            "AnotherTemplate",
        ])
        #expect(scaffoldCommandWithArgs.json == false)
        #expect(scaffoldCommandWithArgs.path == "/new/scaffold/path")
        #expect(scaffoldCommandWithArgs.template == "AnotherTemplate")
    }

    @Test(.withMockedEnvironment()) func testTestCommandWithEnvVars() throws {
        // Set environment variables for TestCommand
        setVariable(.testScheme, value: "MyScheme")
        setVariable(.testClean, value: "true")
        setVariable(.testNoUpload, value: "true")
        setVariable(.testPath, value: "/path/to/test")
        setVariable(.testDevice, value: "iPhone")
        setVariable(.testPlatform, value: "iOS")
        setVariable(.testOS, value: "14.5")
        setVariable(.testRosetta, value: "true")
        setVariable(.testConfiguration, value: "Debug")
        setVariable(.testSkipUITests, value: "true")
        setVariable(.testSkipUnitTests, value: "true")
        setVariable(.testResultBundlePath, value: "/path/to/resultBundle")
        setVariable(.testDerivedDataPath, value: "/path/to/derivedData")
        setVariable(.testRetryCount, value: "2")
        setVariable(.testTestPlan, value: "MyTestPlan")
        setVariable(.testSkipTestTargets, value: "SkipTarget1,SkipTarget2")
        setVariable(.testConfigurations, value: "Config1,Config2")
        setVariable(.testSkipConfigurations, value: "SkipConfig1,SkipConfig2")
        setVariable(.testGenerateOnly, value: "true")
        setVariable(.testBinaryCache, value: "false")
        setVariable(.testSelectiveTesting, value: "false")

        // Execute TestCommand without command line arguments
        let testCommandWithEnvVars = try TestCommand.parse([])
        #expect(testCommandWithEnvVars.scheme == "MyScheme")
        #expect(testCommandWithEnvVars.clean == true)
        #expect(testCommandWithEnvVars.noUpload == true)
        #expect(testCommandWithEnvVars.path == "/path/to/test")
        #expect(testCommandWithEnvVars.device == "iPhone")
        #expect(testCommandWithEnvVars.platform == "iOS")
        #expect(testCommandWithEnvVars.os == "14.5")
        #expect(testCommandWithEnvVars.rosetta == true)
        #expect(testCommandWithEnvVars.configuration == "Debug")
        #expect(testCommandWithEnvVars.skipUITests == true)
        #expect(testCommandWithEnvVars.skipUnitTests == true)
        #expect(testCommandWithEnvVars.resultBundlePath == "/path/to/resultBundle")
        #expect(testCommandWithEnvVars.derivedDataPath == "/path/to/derivedData")
        #expect(testCommandWithEnvVars.retryCount == 2)
        #expect(testCommandWithEnvVars.testPlan == "MyTestPlan")
        #expect(testCommandWithEnvVars.testTargets == [])
        #expect(testCommandWithEnvVars.skipTestTargets == [
            try TestIdentifier(string: "SkipTarget1"),
            try TestIdentifier(string: "SkipTarget2"),
        ])
        #expect(testCommandWithEnvVars.configurations == ["Config1", "Config2"])
        #expect(testCommandWithEnvVars.skipConfigurations == ["SkipConfig1", "SkipConfig2"])
        #expect(testCommandWithEnvVars.generateOnly == true)
        #expect(testCommandWithEnvVars.binaryCache == false)
        #expect(testCommandWithEnvVars.selectiveTesting == false)

        // Execute TestCommand with command line arguments
        let testCommandWithArgs = try TestCommand.parse([
            "NewScheme",
            "--no-clean",
            "--path", "/new/test/path",
            "--device", "iPad",
            "--platform", "macOS",
            "--os", "15.0",
            "--no-rosetta",
            "--configuration", "Release",
            "--no-skip-ui-tests",
            "--result-bundle-path", "/new/resultBundle/path",
            "--derived-data-path", "/new/derivedData/path",
            "--retry-count", "3",
            "--test-plan", "NewTestPlan",
            "--skip-test-targets", "NewSkipTarget1", "NewSkipTarget2",
            "--filter-configurations", "NewConfig1", "NewConfig2",
            "--skip-configurations", "NewSkipConfig1", "NewSkipConfig2",
            "--no-generate-only",
            "--no-binary-cache",
            "--no-selective-testing",
        ])
        #expect(testCommandWithArgs.scheme == "NewScheme")
        #expect(testCommandWithArgs.clean == false)
        #expect(testCommandWithArgs.path == "/new/test/path")
        #expect(testCommandWithArgs.device == "iPad")
        #expect(testCommandWithArgs.platform == "macOS")
        #expect(testCommandWithArgs.os == "15.0")
        #expect(testCommandWithArgs.rosetta == false)
        #expect(testCommandWithArgs.configuration == "Release")
        #expect(testCommandWithArgs.skipUITests == false)
        #expect(testCommandWithArgs.resultBundlePath == "/new/resultBundle/path")
        #expect(testCommandWithArgs.derivedDataPath == "/new/derivedData/path")
        #expect(testCommandWithArgs.retryCount == 3)
        #expect(testCommandWithArgs.testPlan == "NewTestPlan")
        #expect(testCommandWithArgs.testTargets == [])
        #expect(testCommandWithArgs.skipTestTargets == [
            try TestIdentifier(string: "NewSkipTarget1"),
            try TestIdentifier(string: "NewSkipTarget2"),
        ])
        #expect(testCommandWithArgs.configurations == ["NewConfig1", "NewConfig2"])
        #expect(testCommandWithArgs.skipConfigurations == ["NewSkipConfig1", "NewSkipConfig2"])
        #expect(testCommandWithArgs.generateOnly == false)
        #expect(testCommandWithArgs.binaryCache == false)
        #expect(testCommandWithArgs.selectiveTesting == false)
    }

    @Test(.withMockedEnvironment()) func organizationBillingCommandUsesEnvVars() throws {
        setVariable(.organizationBillingOrganizationName, value: "MyOrganization")
        setVariable(.organizationBillingPath, value: "/path/to/billing")

        let commandWithEnvVars = try OrganizationBillingCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.path == "/path/to/billing")

        let commandWithArgs = try OrganizationBillingCommand.parse([
            "AnotherOrganization",
            "--path", "/new/billing/path",
        ])
        #expect(commandWithArgs.organizationName == "AnotherOrganization")
        #expect(commandWithArgs.path == "/new/billing/path")
    }

    @Test(.withMockedEnvironment()) func organizationCreateCommandUsesEnvVars() throws {
        setVariable(.organizationCreateOrganizationName, value: "MyNewOrganization")
        setVariable(.organizationCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try OrganizationCreateCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyNewOrganization")
        #expect(commandWithEnvVars.path == "/path/to/create")

        let commandWithArgs = try OrganizationCreateCommand.parse([
            "AnotherNewOrganization",
            "--path", "/new/create/path",
        ])
        #expect(commandWithArgs.organizationName == "AnotherNewOrganization")
        #expect(commandWithArgs.path == "/new/create/path")
    }

    @Test(.withMockedEnvironment()) func organizationDeleteCommandUsesEnvVars() throws {
        setVariable(.organizationDeleteOrganizationName, value: "OrganizationToDelete")
        setVariable(.organizationDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try OrganizationDeleteCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "OrganizationToDelete")
        #expect(commandWithEnvVars.path == "/path/to/delete")

        let commandWithArgs = try OrganizationDeleteCommand.parse([
            "AnotherOrganizationToDelete",
            "--path", "/new/delete/path",
        ])
        #expect(commandWithArgs.organizationName == "AnotherOrganizationToDelete")
        #expect(commandWithArgs.path == "/new/delete/path")
    }

    @Test(.withMockedEnvironment()) func projectTokensCreateCommandUsesEnvVars() throws {
        setVariable(.projectTokenFullHandle, value: "tuist-org/tuist")
        setVariable(.projectTokenPath, value: "/path/to/token")

        let commandWithEnvVars = try ProjectTokensCreateCommand.parse([])
        #expect(commandWithEnvVars.fullHandle == "tuist-org/tuist")
        #expect(commandWithEnvVars.path == "/path/to/token")

        let commandWithArgs = try ProjectTokensCreateCommand.parse([
            "new-org/new-project",
            "--path", "/new/token/path",
        ])
        #expect(commandWithArgs.fullHandle == "new-org/new-project")
        #expect(commandWithArgs.path == "/new/token/path")
    }

    @Test(.withMockedEnvironment()) func organizationListCommandUsesEnvVars() throws {
        setVariable(.organizationListJson, value: "true")
        setVariable(.organizationListPath, value: "/path/to/list")

        let commandWithEnvVars = try OrganizationListCommand.parse([])
        #expect(commandWithEnvVars.json == true)
        #expect(commandWithEnvVars.path == "/path/to/list")

        let commandWithArgs = try OrganizationListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        #expect(commandWithArgs.json == false)
        #expect(commandWithArgs.path == "/new/list/path")
    }

    @Test(.withMockedEnvironment()) func organizationRemoveInviteCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveInviteOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveInviteEmail, value: "email@example.com")
        setVariable(.organizationRemoveInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try OrganizationRemoveInviteCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.email == "email@example.com")
        #expect(commandWithEnvVars.path == "/path/to/invite")

        let commandWithArgs = try OrganizationRemoveInviteCommand.parse([
            "NewOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.email == "newemail@example.com")
        #expect(commandWithArgs.path == "/new/invite/path")
    }

    @Test(.withMockedEnvironment()) func organizationRemoveMemberCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveMemberOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveMemberUsername, value: "username")
        setVariable(.organizationRemoveMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try OrganizationRemoveMemberCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.username == "username")
        #expect(commandWithEnvVars.path == "/path/to/member")

        let commandWithArgs = try OrganizationRemoveMemberCommand.parse([
            "NewOrganization",
            "newusername",
            "--path", "/new/member/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.username == "newusername")
        #expect(commandWithArgs.path == "/new/member/path")
    }

    @Test(.withMockedEnvironment()) func organizationRemoveSSOCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveSSOOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveSSOPath, value: "/path/to/sso")

        let commandWithEnvVars = try OrganizationRemoveSSOCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.path == "/path/to/sso")

        let commandWithArgs = try OrganizationRemoveSSOCommand.parse([
            "NewOrganization",
            "--path", "/new/sso/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.path == "/new/sso/path")
    }

    @Test(.withMockedEnvironment()) func organizationUpdateSSOCommandUsesEnvVars() throws {
        setVariable(.organizationUpdateSSOOrganizationName, value: "MyOrganization")
        setVariable(.organizationUpdateSSOProvider, value: "google")
        setVariable(.organizationUpdateSSOOrganizationId, value: "1234")
        setVariable(.organizationUpdateSSOPath, value: "/path/to/update/sso")

        let commandWithEnvVars = try OrganizationUpdateSSOCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.provider == .google)
        #expect(commandWithEnvVars.organizationId == "1234")
        #expect(commandWithEnvVars.path == "/path/to/update/sso")

        let commandWithArgs = try OrganizationUpdateSSOCommand.parse([
            "NewOrganization",
            "--provider", "google",
            "--organization-id", "5678",
            "--path", "/new/update/sso/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.provider == .google)
        #expect(commandWithArgs.organizationId == "5678")
        #expect(commandWithArgs.path == "/new/update/sso/path")
    }

    @Test(.withMockedEnvironment()) func projectDeleteCommandUsesEnvVars() throws {
        setVariable(.projectDeleteFullHandle, value: "tuist-org/tuist")
        setVariable(.projectDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try ProjectDeleteCommand.parse([])
        #expect(commandWithEnvVars.fullHandle == "tuist-org/tuist")
        #expect(commandWithEnvVars.path == "/path/to/delete")

        let commandWithArgs = try ProjectDeleteCommand.parse([
            "new-org/new-project",
            "--path", "/new/delete/path",
        ])
        #expect(commandWithArgs.fullHandle == "new-org/new-project")
        #expect(commandWithArgs.path == "/new/delete/path")
    }

    @Test(.withMockedEnvironment()) func projectCreateCommandUsesEnvVars() throws {
        setVariable(.projectCreateFullHandle, value: "tuist-org/tuist")
        setVariable(.projectCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try ProjectCreateCommand.parse([])
        #expect(commandWithEnvVars.fullHandle == "tuist-org/tuist")
        #expect(commandWithEnvVars.path == "/path/to/create")

        let commandWithArgs = try ProjectCreateCommand.parse([
            "new-org/new-project",
            "--path", "/new/create/path",
        ])
        #expect(commandWithArgs.fullHandle == "new-org/new-project")
        #expect(commandWithArgs.path == "/new/create/path")
    }

    @Test(.withMockedEnvironment()) func organizationInviteCommandUsesEnvVars() throws {
        setVariable(.organizationInviteOrganizationName, value: "InviteOrganization")
        setVariable(.organizationInviteEmail, value: "email@example.com")
        setVariable(.organizationInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try OrganizationInviteCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "InviteOrganization")
        #expect(commandWithEnvVars.email == "email@example.com")
        #expect(commandWithEnvVars.path == "/path/to/invite")

        let commandWithArgs = try OrganizationInviteCommand.parse([
            "NewInviteOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        #expect(commandWithArgs.organizationName == "NewInviteOrganization")
        #expect(commandWithArgs.email == "newemail@example.com")
        #expect(commandWithArgs.path == "/new/invite/path")
    }

    @Test(.withMockedEnvironment()) func organizationShowCommandUsesEnvVars() throws {
        setVariable(.organizationShowOrganizationName, value: "MyOrganization")
        setVariable(.organizationShowJson, value: "true")
        setVariable(.organizationShowPath, value: "/path/to/show")

        let commandWithEnvVars = try OrganizationShowCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.json == true)
        #expect(commandWithEnvVars.path == "/path/to/show")

        let commandWithArgs = try OrganizationShowCommand.parse([
            "NewOrganization",
            "--no-json",
            "--path", "/new/show/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.json == false)
        #expect(commandWithArgs.path == "/new/show/path")
    }

    @Test(.withMockedEnvironment()) func projectListCommandUsesEnvVars() throws {
        setVariable(.projectListJson, value: "true")
        setVariable(.projectListPath, value: "/path/to/list")

        let commandWithEnvVars = try ProjectListCommand.parse([])
        #expect(commandWithEnvVars.json == true)
        #expect(commandWithEnvVars.path == "/path/to/list")

        let commandWithArgs = try ProjectListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        #expect(commandWithArgs.json == false)
        #expect(commandWithArgs.path == "/new/list/path")
    }

    @Test(.withMockedEnvironment()) func organizationUpdateMemberCommandUsesEnvVars() throws {
        setVariable(.organizationUpdateMemberOrganizationName, value: "MyOrganization")
        setVariable(.organizationUpdateMemberUsername, value: "username")
        setVariable(.organizationUpdateMemberRole, value: "admin")
        setVariable(.organizationUpdateMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try OrganizationUpdateMemberCommand.parse([])
        #expect(commandWithEnvVars.organizationName == "MyOrganization")
        #expect(commandWithEnvVars.username == "username")
        #expect(commandWithEnvVars.role == "admin")
        #expect(commandWithEnvVars.path == "/path/to/member")

        let commandWithArgs = try OrganizationUpdateMemberCommand.parse([
            "NewOrganization",
            "newusername",
            "--role", "user",
            "--path", "/new/member/path",
        ])
        #expect(commandWithArgs.organizationName == "NewOrganization")
        #expect(commandWithArgs.username == "newusername")
        #expect(commandWithArgs.role == "user")
        #expect(commandWithArgs.path == "/new/member/path")
    }

    @Test(.withMockedEnvironment()) func loginCommandUsesEnvVars() throws {
        setVariable(.authPath, value: "/path/to/auth")

        let commandWithEnvVars = try LoginCommand.parse([])
        #expect(commandWithEnvVars.path == "/path/to/auth")

        let commandWithArgs = try LoginCommand.parse([
            "--path", "/new/auth/path",
        ])
        #expect(commandWithArgs.path == "/new/auth/path")
    }

    @Test(.withMockedEnvironment()) func whoamiCommandUsesEnvVars() throws {
        setVariable(.whoamiPath, value: "/path/to/session")

        let commandWithEnvVars = try WhoamiCommand.parse([])
        #expect(commandWithEnvVars.path == "/path/to/session")

        let commandWithArgs = try WhoamiCommand.parse([
            "--path", "/new/session/path",
        ])
        #expect(commandWithArgs.path == "/new/session/path")
    }

    @Test(.withMockedEnvironment()) func logoutCommandUsesEnvVars() throws {
        setVariable(.logoutPath, value: "/path/to/logout")

        let commandWithEnvVars = try LogoutCommand.parse([])
        #expect(commandWithEnvVars.path == "/path/to/logout")

        let commandWithArgs = try LogoutCommand.parse([
            "--path", "/new/logout/path",
        ])
        #expect(commandWithArgs.path == "/new/logout/path")
    }

    @Test(.withMockedEnvironment()) func cacheCommandUsesEnvVars() throws {
        setVariable(.cacheExternalOnly, value: "true")
        setVariable(.cacheGenerateOnly, value: "true")
        setVariable(.cachePrintHashes, value: "true")
        setVariable(.cacheConfiguration, value: "CacheConfig")
        setVariable(.cachePath, value: "/cache/path")
        setVariable(.cacheTargets, value: "Fmk1,Fmk2")

        let commandWithEnvVars = try CacheCommand.parse([])
        #expect(commandWithEnvVars.externalOnly == true)
        #expect(commandWithEnvVars.generateOnly == true)
        #expect(commandWithEnvVars.printHashes == true)
        #expect(commandWithEnvVars.configuration == "CacheConfig")
        #expect(commandWithEnvVars.path == "/cache/path")
        #expect(commandWithEnvVars.targets == ["Fmk1", "Fmk2"])

        let commandWithArgs = try CacheCommand.parse([
            "--external-only",
            "--generate-only",
            "--print-hashes",
            "--configuration", "CacheConfig",
            "--path", "/cache/path",
            "--",
            "Fmk1", "Fmk2",
        ])
        #expect(commandWithArgs.externalOnly == true)
        #expect(commandWithArgs.generateOnly == true)
        #expect(commandWithArgs.printHashes == true)
        #expect(commandWithArgs.configuration == "CacheConfig")
        #expect(commandWithArgs.path == "/cache/path")
        #expect(commandWithArgs.targets == ["Fmk1", "Fmk2"])
    }
}
