import ArgumentParser
import Difference
import Foundation
import TSCUtility
import XCTest
@testable import TSCBasic
@testable import TuistCore
@testable import TuistKit
@testable import TuistSupport
@testable import TuistSupportTesting

final class CommandEnvironmentVariableTests: XCTestCase {
    private var mockEnvironment: MockEnvironment!

    override func setUp() {
        super.setUp()
        mockEnvironment = try! MockEnvironment()
        Environment.shared = mockEnvironment
    }

    override func tearDown() {
        mockEnvironment = nil
        Environment.shared = Environment()
        super.tearDown()
    }

    private var tuistVariables: [String: String] {
        get {
            return mockEnvironment.tuistVariables
        }
        set {
            mockEnvironment.tuistVariables = newValue
        }
    }

    private func setVariable(_ key: EnvKey, value: String) {
        mockEnvironment.tuistVariables[key.rawValue] = value
    }

    func testBuildCommandUsesEnvVars() throws {
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
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.scheme, "Scheme1")
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.generate)
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.clean)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.path, "/path/to/project")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.device, "iPhone")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.platform, .iOS)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.os, "14.5.0")
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.rosetta)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.configuration, "Debug")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.buildOutputPath, "/path/to/output")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.derivedDataPath, "/path/to/derivedData")
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.generateOnly)
        XCTAssertEqual(
            buildCommandWithEnvVars.buildOptions.passthroughXcodeBuildArguments,
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
        XCTAssertEqual(buildCommandWithArgs.buildOptions.scheme, "Scheme2")
        XCTAssertTrue(buildCommandWithArgs.buildOptions.generate)
        XCTAssertFalse(buildCommandWithArgs.buildOptions.clean)
        XCTAssertEqual(buildCommandWithArgs.buildOptions.path, "/new/path")
        XCTAssertEqual(buildCommandWithArgs.buildOptions.device, "iPad")
        XCTAssertEqual(buildCommandWithArgs.buildOptions.platform, .tvOS)
        XCTAssertFalse(buildCommandWithArgs.buildOptions.rosetta)
        XCTAssertEqual(buildCommandWithArgs.buildOptions.configuration, "Release")
        XCTAssertEqual(buildCommandWithArgs.buildOptions.buildOutputPath, "/new/output")
        XCTAssertEqual(buildCommandWithArgs.buildOptions.derivedDataPath, "/new/derivedData")
        XCTAssertFalse(buildCommandWithArgs.buildOptions.generateOnly)
        XCTAssertEqual(buildCommandWithArgs.buildOptions.passthroughXcodeBuildArguments, ["-configuration", "Debug"])
    }

    func testCleanCommandUsesEnvVars() throws {
        setVariable(.cleanCleanCategories, value: "dependencies")
        setVariable(.cleanPath, value: "/path/to/clean")

        let cleanCommandWithEnvVars = try CleanCommand.parse([])
        XCTAssertEqual(cleanCommandWithEnvVars.cleanCategories, [TuistCleanCategory.dependencies])
        XCTAssertEqual(cleanCommandWithEnvVars.path, "/path/to/clean")

        let cleanCommandWithArgs = try CleanCommand.parse([
            "manifests",
            "--path", "/new/clean/path",
        ])
        XCTAssertEqual(cleanCommandWithArgs.cleanCategories, [TuistCleanCategory.global(.manifests)])
        XCTAssertEqual(cleanCommandWithArgs.path, "/new/clean/path")
    }

    func testDumpCommandUsesEnvVars() throws {
        setVariable(.dumpPath, value: "/path/to/dump")
        setVariable(.dumpManifest, value: "Project")

        let dumpCommandWithEnvVars = try DumpCommand.parse([])
        XCTAssertEqual(dumpCommandWithEnvVars.path, "/path/to/dump")
        XCTAssertEqual(dumpCommandWithEnvVars.manifest, .project)

        let dumpCommandWithArgs = try DumpCommand.parse([
            "workspace",
            "--path", "/new/dump/path",
        ])
        XCTAssertEqual(dumpCommandWithArgs.path, "/new/dump/path")
        XCTAssertEqual(dumpCommandWithArgs.manifest, .workspace)
    }

    func testEditCommandUsesEnvVars() throws {
        setVariable(.editPath, value: "/path/to/edit")
        setVariable(.editPermanent, value: "true")
        setVariable(.editOnlyCurrentDirectory, value: "true")

        let editCommandWithEnvVars = try EditCommand.parse([])
        XCTAssertEqual(editCommandWithEnvVars.path, "/path/to/edit")
        XCTAssertTrue(editCommandWithEnvVars.permanent)
        XCTAssertTrue(editCommandWithEnvVars.onlyCurrentDirectory)

        let editCommandWithArgs = try EditCommand.parse([
            "--path", "/new/edit/path",
            "--no-permanent",
            "--no-only-current-directory",
        ])
        XCTAssertEqual(editCommandWithArgs.path, "/new/edit/path")
        XCTAssertFalse(editCommandWithArgs.permanent)
        XCTAssertFalse(editCommandWithArgs.onlyCurrentDirectory)
    }

    func testGenerateCommandUsesEnvVars() throws {
        setVariable(.generatePath, value: "/path/to/generate")
        setVariable(.generateOpen, value: "false")
        setVariable(.generateBinaryCache, value: "false")

        let generateCommandWithEnvVars = try GenerateCommand.parse([])
        XCTAssertEqual(generateCommandWithEnvVars.path, "/path/to/generate")
        XCTAssertFalse(generateCommandWithEnvVars.open)
        XCTAssertFalse(generateCommandWithEnvVars.binaryCache)

        let generateCommandWithArgs = try GenerateCommand.parse([
            "--path", "/new/generate/path",
            "--open",
            "--binary-cache",
        ])
        XCTAssertEqual(generateCommandWithArgs.path, "/new/generate/path")
        XCTAssertTrue(generateCommandWithArgs.open)
        XCTAssertTrue(generateCommandWithArgs.binaryCache)
    }

    func testGraphCommandUsesEnvVars() throws {
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
        XCTAssertTrue(graphCommandWithEnvVars.skipTestTargets)
        XCTAssertTrue(graphCommandWithEnvVars.skipExternalDependencies)
        XCTAssertEqual(graphCommandWithEnvVars.platform, .iOS)
        XCTAssertEqual(graphCommandWithEnvVars.format, .svg)
        XCTAssertFalse(graphCommandWithEnvVars.open)
        XCTAssertEqual(graphCommandWithEnvVars.layoutAlgorithm, .circo)
        XCTAssertEqual(graphCommandWithEnvVars.targets, ["Target1", "Target2"])
        XCTAssertEqual(graphCommandWithEnvVars.path, "/path/to/graph")
        XCTAssertEqual(graphCommandWithEnvVars.outputPath, "/path/to/output")

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
        XCTAssertFalse(graphCommandWithArgs.skipTestTargets)
        XCTAssertFalse(graphCommandWithArgs.skipExternalDependencies)
        XCTAssertEqual(graphCommandWithArgs.platform, .macOS)
        XCTAssertEqual(graphCommandWithArgs.format, .json)
        XCTAssertTrue(graphCommandWithArgs.open)
        XCTAssertEqual(graphCommandWithArgs.layoutAlgorithm, .fdp)
        XCTAssertEqual(graphCommandWithArgs.targets, ["Target3", "Target4"])
        XCTAssertEqual(graphCommandWithArgs.path, "/new/graph/path")
        XCTAssertEqual(graphCommandWithArgs.outputPath, "/new/graph/output")
    }

    func testInitCommandUsesEnvVars() throws {
        setVariable(.initPlatform, value: "macos")
        setVariable(.initName, value: "MyProject")
        setVariable(.initTemplate, value: "MyTemplate")
        setVariable(.initPath, value: "/path/to/init")

        let initCommandWithEnvVars = try InitCommand.parse([])
        XCTAssertEqual(initCommandWithEnvVars.name, "MyProject")
        XCTAssertEqual(initCommandWithEnvVars.template, "MyTemplate")
        XCTAssertEqual(initCommandWithEnvVars.path, "/path/to/init")

        let initCommandWithArgs = try InitCommand.parse([
            "--platform", "ios",
            "--name", "NewProject",
            "--template", "NewTemplate",
            "--path", "/new/init/path",
        ])
        XCTAssertEqual(initCommandWithArgs.name, "NewProject")
        XCTAssertEqual(initCommandWithArgs.template, "NewTemplate")
        XCTAssertEqual(initCommandWithArgs.path, "/new/init/path")
    }

    func testInstallCommandUsesEnvVars() throws {
        setVariable(.installPath, value: "/path/to/install")
        setVariable(.installUpdate, value: "true")

        let installCommandWithEnvVars = try InstallCommand.parse([])
        XCTAssertEqual(installCommandWithEnvVars.path, "/path/to/install")
        XCTAssertTrue(installCommandWithEnvVars.update)

        let installCommandWithArgs = try InstallCommand.parse([
            "--path", "/new/install/path",
            "--no-update",
        ])
        XCTAssertEqual(installCommandWithArgs.path, "/new/install/path")
        XCTAssertFalse(installCommandWithArgs.update)
    }

    func testListCommandUsesEnvVars() throws {
        setVariable(.scaffoldListJson, value: "true")
        setVariable(.scaffoldListPath, value: "/path/to/list")

        let listCommandWithEnvVars = try ListCommand.parse([])
        XCTAssertTrue(listCommandWithEnvVars.json)
        XCTAssertEqual(listCommandWithEnvVars.path, "/path/to/list")

        let listCommandWithArgs = try ListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        XCTAssertFalse(listCommandWithArgs.json)
        XCTAssertEqual(listCommandWithArgs.path, "/new/list/path")
    }

    func testMigrationCheckEmptyBuildSettingsCommandUsesEnvVars() throws {
        setVariable(.migrationCheckEmptySettingsXcodeprojPath, value: "/path/to/xcodeproj")
        setVariable(.migrationCheckEmptySettingsTarget, value: "MyTarget")

        let migrationCommandWithEnvVars = try MigrationCheckEmptyBuildSettingsCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommandWithEnvVars.target, "MyTarget")

        let migrationCommandWithArgs = try MigrationCheckEmptyBuildSettingsCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--target", "NewTarget",
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommandWithArgs.target, "NewTarget")
    }

    func testMigrationSettingsToXCConfigCommandUsesEnvVars() throws {
        setVariable(.migrationSettingsToXcconfigXcodeprojPath, value: "/path/to/xcodeproj")
        setVariable(.migrationSettingsToXcconfigXcconfigPath, value: "/path/to/xcconfig")
        setVariable(.migrationSettingsToXcconfigTarget, value: "MyTarget")

        let migrationCommandWithEnvVars = try MigrationSettingsToXCConfigCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommandWithEnvVars.xcconfigPath, "/path/to/xcconfig")
        XCTAssertEqual(migrationCommandWithEnvVars.target, "MyTarget")

        let migrationCommandWithArgs = try MigrationSettingsToXCConfigCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--xcconfig-path", "/new/xcconfig/path",
            "--target", "NewTarget",
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommandWithArgs.xcconfigPath, "/new/xcconfig/path")
        XCTAssertEqual(migrationCommandWithArgs.target, "NewTarget")
    }

    func testMigrationTargetsByDependenciesCommandUsesEnvVars() throws {
        setVariable(.migrationListTargetsXcodeprojPath, value: "/path/to/xcodeproj")

        let migrationCommandWithEnvVars = try MigrationTargetsByDependenciesCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")

        let migrationCommandWithArgs = try MigrationTargetsByDependenciesCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
    }

    func testPluginArchiveCommandUsesEnvVars() throws {
        setVariable(.pluginArchivePath, value: "/path/to/plugin")

        let pluginCommandWithEnvVars = try PluginArchiveCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.path, "/path/to/plugin")

        let pluginCommandWithArgs = try PluginArchiveCommand.parse([
            "--path", "/new/plugin/path",
        ])
        XCTAssertEqual(pluginCommandWithArgs.path, "/new/plugin/path")
    }

    func testPluginBuildCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginBuildBuildTests, value: "true")
        setVariable(.pluginBuildShowBinPath, value: "true")
        setVariable(.pluginBuildTargets, value: "Target1,Target2")
        setVariable(.pluginBuildProducts, value: "Product1,Product2")

        let pluginCommandWithEnvVars = try PluginBuildCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.path, "/path/to/plugin")
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.configuration, .debug)
        XCTAssertTrue(pluginCommandWithEnvVars.buildTests)
        XCTAssertTrue(pluginCommandWithEnvVars.showBinPath)
        XCTAssertEqual(pluginCommandWithEnvVars.targets, ["Target1", "Target2"])
        XCTAssertEqual(pluginCommandWithEnvVars.products, ["Product1", "Product2"])

        let pluginCommandWithArgs = try PluginBuildCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--no-show-bin-path",
            "--targets", "Target3", "--targets", "Target4",
            "--products", "Product3", "--products", "Product4",
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertFalse(pluginCommandWithArgs.showBinPath)
        XCTAssertEqual(pluginCommandWithArgs.targets, ["Target3", "Target4"])
        XCTAssertEqual(pluginCommandWithArgs.products, ["Product3", "Product4"])
    }

    func testPluginRunCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginRunBuildTests, value: "true")
        setVariable(.pluginRunSkipBuild, value: "true")
        setVariable(.pluginRunTask, value: "myTask")
        setVariable(.pluginRunArguments, value: "arg1,arg2,arg3")

        let pluginCommandWithEnvVars = try PluginRunCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.path, "/path/to/plugin")
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.configuration, .debug)
        XCTAssertTrue(pluginCommandWithEnvVars.buildTests)
        XCTAssertTrue(pluginCommandWithEnvVars.skipBuild)
        XCTAssertEqual(pluginCommandWithEnvVars.task, "myTask")
        XCTAssertEqual(pluginCommandWithEnvVars.arguments, ["arg1", "arg2", "arg3"])

        let pluginCommandWithArgs = try PluginRunCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--no-skip-build",
            "otherTask",
            "arg4", "arg5",
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertFalse(pluginCommandWithArgs.skipBuild)
        XCTAssertEqual(pluginCommandWithArgs.task, "otherTask")
        XCTAssertEqual(pluginCommandWithArgs.arguments, ["arg4", "arg5"])
    }

    func testPluginTestCommandUsesEnvVars() throws {
        setVariable(.pluginOptionsPath, value: "/path/to/plugin")
        setVariable(.pluginOptionsConfiguration, value: "debug")
        setVariable(.pluginTestBuildTests, value: "true")
        setVariable(.pluginTestTestProducts, value: "Product1,Product2")

        let pluginCommandWithEnvVars = try PluginTestCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.path, "/path/to/plugin")
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.configuration, .debug)
        XCTAssertTrue(pluginCommandWithEnvVars.buildTests)
        XCTAssertEqual(pluginCommandWithEnvVars.testProducts, ["Product1", "Product2"])

        let pluginCommandWithArgs = try PluginTestCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--test-products", "Product3", "--test-products", "Product4",
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertEqual(pluginCommandWithArgs.testProducts, ["Product3", "Product4"])
    }

    func testRunCommandUsesEnvVars() throws {
        // Set environment variables for RunCommand
        setVariable(.runGenerate, value: "true")
        setVariable(.runClean, value: "true")
        setVariable(.runOS, value: "14.5")
        setVariable(.runScheme, value: "MyScheme")
        setVariable(.runArguments, value: "arg1,arg2,arg3")

        // Execute RunCommand without command line arguments
        let runCommandWithEnvVars = try RunCommand.parse([])
        XCTAssertTrue(runCommandWithEnvVars.generate)
        XCTAssertTrue(runCommandWithEnvVars.clean)
        XCTAssertEqual(runCommandWithEnvVars.os, "14.5")
        XCTAssertEqual(runCommandWithEnvVars.scheme, "MyScheme")
        XCTAssertEqual(runCommandWithEnvVars.arguments, ["arg1", "arg2", "arg3"])

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
        XCTAssertFalse(runCommandWithArgs.generate)
        XCTAssertFalse(runCommandWithArgs.clean)
        XCTAssertEqual(runCommandWithArgs.path, "/new/run/path")
        XCTAssertEqual(runCommandWithArgs.configuration, "Release")
        XCTAssertEqual(runCommandWithArgs.device, "iPhone 12")
        XCTAssertEqual(runCommandWithArgs.os, "15.0")
        XCTAssertTrue(runCommandWithArgs.rosetta)
        XCTAssertEqual(runCommandWithArgs.scheme, "AnotherScheme")
        XCTAssertEqual(runCommandWithArgs.arguments, ["arg4", "arg5"])
    }

    func testScaffoldCommandUsesEnvVars() throws {
        // Set environment variables for ScaffoldCommand
        setVariable(.scaffoldJson, value: "true")
        setVariable(.scaffoldPath, value: "/path/to/scaffold")
        setVariable(.scaffoldTemplate, value: "MyTemplate")

        // Execute ScaffoldCommand without command line arguments
        let scaffoldCommandWithEnvVars = try ScaffoldCommand.parse([])
        XCTAssertTrue(scaffoldCommandWithEnvVars.json)
        XCTAssertEqual(scaffoldCommandWithEnvVars.path, "/path/to/scaffold")
        XCTAssertEqual(scaffoldCommandWithEnvVars.template, "MyTemplate")

        // Execute ScaffoldCommand with command line arguments
        let scaffoldCommandWithArgs = try ScaffoldCommand.parse([
            "--no-json",
            "--path", "/new/scaffold/path",
            "AnotherTemplate",
        ])
        XCTAssertFalse(scaffoldCommandWithArgs.json)
        XCTAssertEqual(scaffoldCommandWithArgs.path, "/new/scaffold/path")
        XCTAssertEqual(scaffoldCommandWithArgs.template, "AnotherTemplate")
    }

    func testTestCommandWithEnvVars() throws {
        // Set environment variables for TestCommand
        setVariable(.testScheme, value: "MyScheme")
        setVariable(.testClean, value: "true")
        setVariable(.testPath, value: "/path/to/test")
        setVariable(.testDevice, value: "iPhone")
        setVariable(.testPlatform, value: "iOS")
        setVariable(.testOS, value: "14.5")
        setVariable(.testRosetta, value: "true")
        setVariable(.testConfiguration, value: "Debug")
        setVariable(.testSkipUITests, value: "true")
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
        XCTAssertEqual(testCommandWithEnvVars.scheme, "MyScheme")
        XCTAssertTrue(testCommandWithEnvVars.clean)
        XCTAssertEqual(testCommandWithEnvVars.path, "/path/to/test")
        XCTAssertEqual(testCommandWithEnvVars.device, "iPhone")
        XCTAssertEqual(testCommandWithEnvVars.platform, "iOS")
        XCTAssertEqual(testCommandWithEnvVars.os, "14.5")
        XCTAssertTrue(testCommandWithEnvVars.rosetta)
        XCTAssertEqual(testCommandWithEnvVars.configuration, "Debug")
        XCTAssertTrue(testCommandWithEnvVars.skipUITests)
        XCTAssertEqual(testCommandWithEnvVars.resultBundlePath, "/path/to/resultBundle")
        XCTAssertEqual(testCommandWithEnvVars.derivedDataPath, "/path/to/derivedData")
        XCTAssertEqual(testCommandWithEnvVars.retryCount, 2)
        XCTAssertEqual(testCommandWithEnvVars.testPlan, "MyTestPlan")
        XCTAssertEqual(testCommandWithEnvVars.testTargets, [])
        XCTAssertEqual(testCommandWithEnvVars.skipTestTargets, [
            try TestIdentifier(string: "SkipTarget1"),
            try TestIdentifier(string: "SkipTarget2"),
        ])
        XCTAssertEqual(testCommandWithEnvVars.configurations, ["Config1", "Config2"])
        XCTAssertEqual(testCommandWithEnvVars.skipConfigurations, ["SkipConfig1", "SkipConfig2"])
        XCTAssertTrue(testCommandWithEnvVars.generateOnly)
        XCTAssertFalse(testCommandWithEnvVars.binaryCache)
        XCTAssertFalse(testCommandWithEnvVars.selectiveTesting)

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
        XCTAssertEqual(testCommandWithArgs.scheme, "NewScheme")
        XCTAssertFalse(testCommandWithArgs.clean)
        XCTAssertEqual(testCommandWithArgs.path, "/new/test/path")
        XCTAssertEqual(testCommandWithArgs.device, "iPad")
        XCTAssertEqual(testCommandWithArgs.platform, "macOS")
        XCTAssertEqual(testCommandWithArgs.os, "15.0")
        XCTAssertFalse(testCommandWithArgs.rosetta)
        XCTAssertEqual(testCommandWithArgs.configuration, "Release")
        XCTAssertFalse(testCommandWithArgs.skipUITests)
        XCTAssertEqual(testCommandWithArgs.resultBundlePath, "/new/resultBundle/path")
        XCTAssertEqual(testCommandWithArgs.derivedDataPath, "/new/derivedData/path")
        XCTAssertEqual(testCommandWithArgs.retryCount, 3)
        XCTAssertEqual(testCommandWithArgs.testPlan, "NewTestPlan")
        XCTAssertEqual(testCommandWithArgs.testTargets, [])
        XCTAssertEqual(testCommandWithArgs.skipTestTargets, [
            try TestIdentifier(string: "NewSkipTarget1"),
            try TestIdentifier(string: "NewSkipTarget2"),
        ])
        XCTAssertEqual(testCommandWithArgs.configurations, ["NewConfig1", "NewConfig2"])
        XCTAssertEqual(testCommandWithArgs.skipConfigurations, ["NewSkipConfig1", "NewSkipConfig2"])
        XCTAssertFalse(testCommandWithArgs.generateOnly)
        XCTAssertFalse(testCommandWithArgs.binaryCache)
        XCTAssertFalse(testCommandWithArgs.selectiveTesting)
    }

    func testCloudOrganizationBillingCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationBillingOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationBillingPath, value: "/path/to/billing")

        let commandWithEnvVars = try CloudOrganizationBillingCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/billing")

        let commandWithArgs = try CloudOrganizationBillingCommand.parse([
            "AnotherOrganization",
            "--path", "/new/billing/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/billing/path")
    }

    func testCloudOrganizationCreateCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationCreateOrganizationName, value: "MyNewOrganization")
        setVariable(.cloudOrganizationCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try CloudOrganizationCreateCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyNewOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/create")

        let commandWithArgs = try CloudOrganizationCreateCommand.parse([
            "AnotherNewOrganization",
            "--path", "/new/create/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherNewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/create/path")
    }

    func testCloudOrganizationDeleteCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationDeleteOrganizationName, value: "OrganizationToDelete")
        setVariable(.cloudOrganizationDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try CloudOrganizationDeleteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "OrganizationToDelete")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/delete")

        let commandWithArgs = try CloudOrganizationDeleteCommand.parse([
            "AnotherOrganizationToDelete",
            "--path", "/new/delete/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherOrganizationToDelete")
        XCTAssertEqual(commandWithArgs.path, "/new/delete/path")
    }

    func testCloudProjectTokenCommandUsesEnvVars() throws {
        setVariable(.cloudProjectTokenProjectName, value: "ProjectName")
        setVariable(.cloudProjectTokenOrganizationName, value: "OrganizationName")
        setVariable(.cloudProjectTokenPath, value: "/path/to/token")

        let commandWithEnvVars = try CloudProjectTokenCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.projectName, "ProjectName")
        XCTAssertEqual(commandWithEnvVars.organizationName, "OrganizationName")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/token")

        let commandWithArgs = try CloudProjectTokenCommand.parse([
            "NewProjectName",
            "--organization-name", "NewOrganizationName",
            "--path", "/new/token/path",
        ])
        XCTAssertEqual(commandWithArgs.projectName, "NewProjectName")
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganizationName")
        XCTAssertEqual(commandWithArgs.path, "/new/token/path")
    }

    func testCloudOrganizationListCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationListJson, value: "true")
        setVariable(.cloudOrganizationListPath, value: "/path/to/list")

        let commandWithEnvVars = try CloudOrganizationListCommand.parse([])
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/list")

        let commandWithArgs = try CloudOrganizationListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/list/path")
    }

    func testCloudOrganizationRemoveInviteCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationRemoveInviteOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationRemoveInviteEmail, value: "email@example.com")
        setVariable(.cloudOrganizationRemoveInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try CloudOrganizationRemoveInviteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.email, "email@example.com")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/invite")

        let commandWithArgs = try CloudOrganizationRemoveInviteCommand.parse([
            "NewOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.email, "newemail@example.com")
        XCTAssertEqual(commandWithArgs.path, "/new/invite/path")
    }

    func testCloudOrganizationRemoveMemberCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationRemoveMemberOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationRemoveMemberUsername, value: "username")
        setVariable(.cloudOrganizationRemoveMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try CloudOrganizationRemoveMemberCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.username, "username")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/member")

        let commandWithArgs = try CloudOrganizationRemoveMemberCommand.parse([
            "NewOrganization",
            "newusername",
            "--path", "/new/member/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.username, "newusername")
        XCTAssertEqual(commandWithArgs.path, "/new/member/path")
    }

    func testCloudOrganizationRemoveSSOCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationRemoveSSOOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationRemoveSSOPath, value: "/path/to/sso")

        let commandWithEnvVars = try CloudOrganizationRemoveSSOCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/sso")

        let commandWithArgs = try CloudOrganizationRemoveSSOCommand.parse([
            "NewOrganization",
            "--path", "/new/sso/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/sso/path")
    }

    func testCloudOrganizationUpdateSSOCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationUpdateSSOOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationUpdateSSOProvider, value: "google")
        setVariable(.cloudOrganizationUpdateSSOOrganizationId, value: "1234")
        setVariable(.cloudOrganizationUpdateSSOPath, value: "/path/to/update/sso")

        let commandWithEnvVars = try CloudOrganizationUpdateSSOCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.provider, .google)
        XCTAssertEqual(commandWithEnvVars.organizationId, "1234")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/update/sso")

        let commandWithArgs = try CloudOrganizationUpdateSSOCommand.parse([
            "NewOrganization",
            "--provider", "google",
            "--organization-id", "5678",
            "--path", "/new/update/sso/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.provider, .google)
        XCTAssertEqual(commandWithArgs.organizationId, "5678")
        XCTAssertEqual(commandWithArgs.path, "/new/update/sso/path")
    }

    func testCloudProjectDeleteCommandUsesEnvVars() throws {
        setVariable(.cloudProjectDeleteProject, value: "MyProject")
        setVariable(.cloudProjectDeleteOrganization, value: "MyOrganization")
        setVariable(.cloudProjectDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try CloudProjectDeleteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.project, "MyProject")
        XCTAssertEqual(commandWithEnvVars.organization, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/delete")

        let commandWithArgs = try CloudProjectDeleteCommand.parse([
            "NewProject",
            "--organization", "NewOrganization",
            "--path", "/new/delete/path",
        ])
        XCTAssertEqual(commandWithArgs.project, "NewProject")
        XCTAssertEqual(commandWithArgs.organization, "NewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/delete/path")
    }

    func testCloudProjectCreateCommandUsesEnvVars() throws {
        setVariable(.cloudProjectCreateName, value: "MyProject")
        setVariable(.cloudProjectCreateOrganization, value: "MyOrganization")
        setVariable(.cloudProjectCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try CloudProjectCreateCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.name, "MyProject")
        XCTAssertEqual(commandWithEnvVars.organization, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/create")

        let commandWithArgs = try CloudProjectCreateCommand.parse([
            "NewProject",
            "--organization", "NewOrganization",
            "--path", "/new/create/path",
        ])
        XCTAssertEqual(commandWithArgs.name, "NewProject")
        XCTAssertEqual(commandWithArgs.organization, "NewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/create/path")
    }

    func testCloudInitCommandUsesEnvVars() throws {
        setVariable(.cloudInitName, value: "InitName")
        setVariable(.cloudInitOrganization, value: "InitOrganization")
        setVariable(.cloudInitPath, value: "/path/to/init")

        let commandWithEnvVars = try CloudInitCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.name, "InitName")
        XCTAssertEqual(commandWithEnvVars.organization, "InitOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/init")

        let commandWithArgs = try CloudInitCommand.parse([
            "NewInitName",
            "--organization", "NewInitOrganization",
            "--path", "/new/init/path",
        ])
        XCTAssertEqual(commandWithArgs.name, "NewInitName")
        XCTAssertEqual(commandWithArgs.organization, "NewInitOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/init/path")
    }

    func testCloudOrganizationInviteCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationInviteOrganizationName, value: "InviteOrganization")
        setVariable(.cloudOrganizationInviteEmail, value: "email@example.com")
        setVariable(.cloudOrganizationInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try CloudOrganizationInviteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "InviteOrganization")
        XCTAssertEqual(commandWithEnvVars.email, "email@example.com")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/invite")

        let commandWithArgs = try CloudOrganizationInviteCommand.parse([
            "NewInviteOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewInviteOrganization")
        XCTAssertEqual(commandWithArgs.email, "newemail@example.com")
        XCTAssertEqual(commandWithArgs.path, "/new/invite/path")
    }

    func testCloudOrganizationShowCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationShowOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationShowJson, value: "true")
        setVariable(.cloudOrganizationShowPath, value: "/path/to/show")

        let commandWithEnvVars = try CloudOrganizationShowCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/show")

        let commandWithArgs = try CloudOrganizationShowCommand.parse([
            "NewOrganization",
            "--no-json",
            "--path", "/new/show/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/show/path")
    }

    func testCloudProjectListCommandUsesEnvVars() throws {
        setVariable(.cloudProjectListJson, value: "true")
        setVariable(.cloudProjectListPath, value: "/path/to/list")

        let commandWithEnvVars = try CloudProjectListCommand.parse([])
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/list")

        let commandWithArgs = try CloudProjectListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/list/path")
    }

    func testCloudOrganizationUpdateMemberCommandUsesEnvVars() throws {
        setVariable(.cloudOrganizationUpdateMemberOrganizationName, value: "MyOrganization")
        setVariable(.cloudOrganizationUpdateMemberUsername, value: "username")
        setVariable(.cloudOrganizationUpdateMemberRole, value: "admin")
        setVariable(.cloudOrganizationUpdateMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try CloudOrganizationUpdateMemberCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.username, "username")
        XCTAssertEqual(commandWithEnvVars.role, "admin")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/member")

        let commandWithArgs = try CloudOrganizationUpdateMemberCommand.parse([
            "NewOrganization",
            "newusername",
            "--role", "user",
            "--path", "/new/member/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.username, "newusername")
        XCTAssertEqual(commandWithArgs.role, "user")
        XCTAssertEqual(commandWithArgs.path, "/new/member/path")
    }

    func testCloudAuthCommandUsesEnvVars() throws {
        setVariable(.cloudAuthPath, value: "/path/to/auth")

        let commandWithEnvVars = try CloudAuthCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/auth")

        let commandWithArgs = try CloudAuthCommand.parse([
            "--path", "/new/auth/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/auth/path")
    }

    func testCloudSessionCommandUsesEnvVars() throws {
        setVariable(.cloudSessionPath, value: "/path/to/session")

        let commandWithEnvVars = try CloudSessionCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/session")

        let commandWithArgs = try CloudSessionCommand.parse([
            "--path", "/new/session/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/session/path")
    }

    func testCloudLogoutCommandUsesEnvVars() throws {
        setVariable(.cloudLogoutPath, value: "/path/to/logout")

        let commandWithEnvVars = try CloudLogoutCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/logout")

        let commandWithArgs = try CloudLogoutCommand.parse([
            "--path", "/new/logout/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/logout/path")
    }

    func testCloudAnalyticsCommandUsesEnvVars() throws {
        setVariable(.cloudAnalyticsPath, value: "/path/to/analytics")

        let commandWithEnvVars = try CloudAnalyticsCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/analytics")

        let commandWithArgs = try CloudAnalyticsCommand.parse([
            "--path", "/new/analytics/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/analytics/path")
    }

    func testCloudCleanCommandUsesEnvVars() throws {
        setVariable(.cloudCleanPath, value: "/path/to/clean")

        let commandWithEnvVars = try CloudCleanCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/clean")

        let commandWithArgs = try CloudCleanCommand.parse([
            "--path", "/new/clean/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/clean/path")
    }
}
