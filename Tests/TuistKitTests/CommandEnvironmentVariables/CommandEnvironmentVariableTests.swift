import ArgumentParser
import Difference
import Foundation
import TSCUtility
import XCTest
@testable import Path
@testable import TuistCore
@testable import TuistKit
@testable import TuistSupport
@testable import TuistSupportTesting

final class CommandEnvironmentVariableTests: XCTestCase {
    private var mockEnvironment: MockEnvironment!

    override func setUp() {
        super.setUp()
        mockEnvironment = try! MockEnvironment()
        Environment._shared.mutate { $0 = mockEnvironment }
    }

    override func tearDown() {
        mockEnvironment = nil
        Environment._shared.mutate { $0 = Environment() }
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
        XCTAssertEqual(runCommandWithEnvVars.runnable, .scheme("MyScheme"))
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
        XCTAssertEqual(runCommandWithArgs.runnable, .scheme("AnotherScheme"))
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

    func testOrganizationBillingCommandUsesEnvVars() throws {
        setVariable(.organizationBillingOrganizationName, value: "MyOrganization")
        setVariable(.organizationBillingPath, value: "/path/to/billing")

        let commandWithEnvVars = try OrganizationBillingCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/billing")

        let commandWithArgs = try OrganizationBillingCommand.parse([
            "AnotherOrganization",
            "--path", "/new/billing/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/billing/path")
    }

    func testOrganizationCreateCommandUsesEnvVars() throws {
        setVariable(.organizationCreateOrganizationName, value: "MyNewOrganization")
        setVariable(.organizationCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try OrganizationCreateCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyNewOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/create")

        let commandWithArgs = try OrganizationCreateCommand.parse([
            "AnotherNewOrganization",
            "--path", "/new/create/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherNewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/create/path")
    }

    func testOrganizationDeleteCommandUsesEnvVars() throws {
        setVariable(.organizationDeleteOrganizationName, value: "OrganizationToDelete")
        setVariable(.organizationDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try OrganizationDeleteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "OrganizationToDelete")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/delete")

        let commandWithArgs = try OrganizationDeleteCommand.parse([
            "AnotherOrganizationToDelete",
            "--path", "/new/delete/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "AnotherOrganizationToDelete")
        XCTAssertEqual(commandWithArgs.path, "/new/delete/path")
    }

    func testProjectTokensCreateCommandUsesEnvVars() throws {
        setVariable(.projectTokenFullHandle, value: "tuist-org/tuist")
        setVariable(.projectTokenPath, value: "/path/to/token")

        let commandWithEnvVars = try ProjectTokensCreateCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.fullHandle, "tuist-org/tuist")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/token")

        let commandWithArgs = try ProjectTokensCreateCommand.parse([
            "new-org/new-project",
            "--path", "/new/token/path",
        ])
        XCTAssertEqual(commandWithArgs.fullHandle, "new-org/new-project")
        XCTAssertEqual(commandWithArgs.path, "/new/token/path")
    }

    func testOrganizationListCommandUsesEnvVars() throws {
        setVariable(.organizationListJson, value: "true")
        setVariable(.organizationListPath, value: "/path/to/list")

        let commandWithEnvVars = try OrganizationListCommand.parse([])
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/list")

        let commandWithArgs = try OrganizationListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/list/path")
    }

    func testOrganizationRemoveInviteCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveInviteOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveInviteEmail, value: "email@example.com")
        setVariable(.organizationRemoveInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try OrganizationRemoveInviteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.email, "email@example.com")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/invite")

        let commandWithArgs = try OrganizationRemoveInviteCommand.parse([
            "NewOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.email, "newemail@example.com")
        XCTAssertEqual(commandWithArgs.path, "/new/invite/path")
    }

    func testOrganizationRemoveMemberCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveMemberOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveMemberUsername, value: "username")
        setVariable(.organizationRemoveMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try OrganizationRemoveMemberCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.username, "username")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/member")

        let commandWithArgs = try OrganizationRemoveMemberCommand.parse([
            "NewOrganization",
            "newusername",
            "--path", "/new/member/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.username, "newusername")
        XCTAssertEqual(commandWithArgs.path, "/new/member/path")
    }

    func testOrganizationRemoveSSOCommandUsesEnvVars() throws {
        setVariable(.organizationRemoveSSOOrganizationName, value: "MyOrganization")
        setVariable(.organizationRemoveSSOPath, value: "/path/to/sso")

        let commandWithEnvVars = try OrganizationRemoveSSOCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/sso")

        let commandWithArgs = try OrganizationRemoveSSOCommand.parse([
            "NewOrganization",
            "--path", "/new/sso/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertEqual(commandWithArgs.path, "/new/sso/path")
    }

    func testOrganizationUpdateSSOCommandUsesEnvVars() throws {
        setVariable(.organizationUpdateSSOOrganizationName, value: "MyOrganization")
        setVariable(.organizationUpdateSSOProvider, value: "google")
        setVariable(.organizationUpdateSSOOrganizationId, value: "1234")
        setVariable(.organizationUpdateSSOPath, value: "/path/to/update/sso")

        let commandWithEnvVars = try OrganizationUpdateSSOCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.provider, .google)
        XCTAssertEqual(commandWithEnvVars.organizationId, "1234")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/update/sso")

        let commandWithArgs = try OrganizationUpdateSSOCommand.parse([
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

    func testProjectDeleteCommandUsesEnvVars() throws {
        setVariable(.projectDeleteFullHandle, value: "tuist-org/tuist")
        setVariable(.projectDeletePath, value: "/path/to/delete")

        let commandWithEnvVars = try ProjectDeleteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.fullHandle, "tuist-org/tuist")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/delete")

        let commandWithArgs = try ProjectDeleteCommand.parse([
            "new-org/new-project",
            "--path", "/new/delete/path",
        ])
        XCTAssertEqual(commandWithArgs.fullHandle, "new-org/new-project")
        XCTAssertEqual(commandWithArgs.path, "/new/delete/path")
    }

    func testProjectCreateCommandUsesEnvVars() throws {
        setVariable(.projectCreateFullHandle, value: "tuist-org/tuist")
        setVariable(.projectCreatePath, value: "/path/to/create")

        let commandWithEnvVars = try ProjectCreateCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.fullHandle, "tuist-org/tuist")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/create")

        let commandWithArgs = try ProjectCreateCommand.parse([
            "new-org/new-project",
            "--path", "/new/create/path",
        ])
        XCTAssertEqual(commandWithArgs.fullHandle, "new-org/new-project")
        XCTAssertEqual(commandWithArgs.path, "/new/create/path")
    }

    func testOrganizationInviteCommandUsesEnvVars() throws {
        setVariable(.organizationInviteOrganizationName, value: "InviteOrganization")
        setVariable(.organizationInviteEmail, value: "email@example.com")
        setVariable(.organizationInvitePath, value: "/path/to/invite")

        let commandWithEnvVars = try OrganizationInviteCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "InviteOrganization")
        XCTAssertEqual(commandWithEnvVars.email, "email@example.com")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/invite")

        let commandWithArgs = try OrganizationInviteCommand.parse([
            "NewInviteOrganization",
            "newemail@example.com",
            "--path", "/new/invite/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewInviteOrganization")
        XCTAssertEqual(commandWithArgs.email, "newemail@example.com")
        XCTAssertEqual(commandWithArgs.path, "/new/invite/path")
    }

    func testOrganizationShowCommandUsesEnvVars() throws {
        setVariable(.organizationShowOrganizationName, value: "MyOrganization")
        setVariable(.organizationShowJson, value: "true")
        setVariable(.organizationShowPath, value: "/path/to/show")

        let commandWithEnvVars = try OrganizationShowCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/show")

        let commandWithArgs = try OrganizationShowCommand.parse([
            "NewOrganization",
            "--no-json",
            "--path", "/new/show/path",
        ])
        XCTAssertEqual(commandWithArgs.organizationName, "NewOrganization")
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/show/path")
    }

    func testProjectListCommandUsesEnvVars() throws {
        setVariable(.projectListJson, value: "true")
        setVariable(.projectListPath, value: "/path/to/list")

        let commandWithEnvVars = try ProjectListCommand.parse([])
        XCTAssertTrue(commandWithEnvVars.json)
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/list")

        let commandWithArgs = try ProjectListCommand.parse([
            "--no-json",
            "--path", "/new/list/path",
        ])
        XCTAssertFalse(commandWithArgs.json)
        XCTAssertEqual(commandWithArgs.path, "/new/list/path")
    }

    func testOrganizationUpdateMemberCommandUsesEnvVars() throws {
        setVariable(.organizationUpdateMemberOrganizationName, value: "MyOrganization")
        setVariable(.organizationUpdateMemberUsername, value: "username")
        setVariable(.organizationUpdateMemberRole, value: "admin")
        setVariable(.organizationUpdateMemberPath, value: "/path/to/member")

        let commandWithEnvVars = try OrganizationUpdateMemberCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.organizationName, "MyOrganization")
        XCTAssertEqual(commandWithEnvVars.username, "username")
        XCTAssertEqual(commandWithEnvVars.role, "admin")
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/member")

        let commandWithArgs = try OrganizationUpdateMemberCommand.parse([
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

    func testAuthCommandUsesEnvVars() throws {
        setVariable(.authPath, value: "/path/to/auth")

        let commandWithEnvVars = try AuthCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/auth")

        let commandWithArgs = try AuthCommand.parse([
            "--path", "/new/auth/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/auth/path")
    }

    func testSessionCommandUsesEnvVars() throws {
        setVariable(.sessionPath, value: "/path/to/session")

        let commandWithEnvVars = try SessionCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/session")

        let commandWithArgs = try SessionCommand.parse([
            "--path", "/new/session/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/session/path")
    }

    func testLogoutCommandUsesEnvVars() throws {
        setVariable(.logoutPath, value: "/path/to/logout")

        let commandWithEnvVars = try LogoutCommand.parse([])
        XCTAssertEqual(commandWithEnvVars.path, "/path/to/logout")

        let commandWithArgs = try LogoutCommand.parse([
            "--path", "/new/logout/path",
        ])
        XCTAssertEqual(commandWithArgs.path, "/new/logout/path")
    }
}
