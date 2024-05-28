@testable import ArgumentParser
import Difference
import Foundation
import TSCBasic
import XCTest
import TSCUtility
@testable import TSCBasic
@testable import TuistCore
@testable import TuistSupport
@testable import TuistKit
@testable import TuistSupportTesting

final class ArgumentParserEnvTests: XCTestCase {
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
    
    func testBuildCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.buildOptionsSchemes.rawValue] = "Scheme1,Scheme2"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsGenerate.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsClean.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsPath.rawValue] = "/path/to/project"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsDevice.rawValue] = "iPhone"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsPlatform.rawValue] = "ios"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsOS.rawValue] = "14.5.0"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsRosetta.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsConfiguration.rawValue] = "Debug"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsOutputPath.rawValue] = "/path/to/output"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsDerivedDataPath.rawValue] = "/path/to/derivedData"
        mockEnvironment.tuistVariables[EnvKey.buildOptionsGenerateOnly.rawValue] = "true"
        
        let buildCommandWithEnvVars = try BuildCommand.parse([])
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.schemes, ["Scheme1", "Scheme2"])
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.generate)
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.clean)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.path, "/path/to/project")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.device, "iPhone")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.platform, .iOS)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.os, try Version(versionString: "14.5.0"))
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.rosetta)
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.configuration, "Debug")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.buildOutputPath, "/path/to/output")
        XCTAssertEqual(buildCommandWithEnvVars.buildOptions.derivedDataPath, "/path/to/derivedData")
        XCTAssertTrue(buildCommandWithEnvVars.buildOptions.generateOnly)
        
        let buildCommandWithArgs = try BuildCommand.parse([
            "Scheme3",
            "--generate",
            "--no-clean",
            "--path", "/new/path",
            "--device", "iPad",
            "--platform", "tvos",
            "--no-rosetta",
            "--configuration", "Release",
            "--build-output-path", "/new/output",
            "--derived-data-path", "/new/derivedData",
            "--no-generate-only"
        ])
        XCTAssertEqual(buildCommandWithArgs.buildOptions.schemes, ["Scheme3"])
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
    }
    
    func testCleanCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.cleanCleanCategories.rawValue] = "dependencies"
        mockEnvironment.tuistVariables[EnvKey.cleanPath.rawValue] = "/path/to/clean"

        let cleanCommandWithEnvVars = try CleanCommand<TuistCleanCategory>.parse([])
        XCTAssertEqual(cleanCommandWithEnvVars.cleanCategories, [TuistCleanCategory.dependencies])
        XCTAssertEqual(cleanCommandWithEnvVars.path, "/path/to/clean")

        let cleanCommandWithArgs = try CleanCommand<TuistCleanCategory>.parse([
            "manifests",
            "--path", "/new/clean/path"
        ])
        XCTAssertEqual(cleanCommandWithArgs.cleanCategories, [TuistCleanCategory.global(.manifests)])
        XCTAssertEqual(cleanCommandWithArgs.path, "/new/clean/path")
    }
    
    func testEditCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.editPath.rawValue] = "/path/to/edit"
        mockEnvironment.tuistVariables[EnvKey.editPermanent.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.editOnlyCurrentDirectory.rawValue] = "true"
        
        let editCommandWithEnvVars = try EditCommand.parse([])
        XCTAssertEqual(editCommandWithEnvVars.path, "/path/to/edit")
        XCTAssertTrue(editCommandWithEnvVars.permanent)
        XCTAssertTrue(editCommandWithEnvVars.onlyCurrentDirectory)
        
        let editCommandWithArgs = try EditCommand.parse([
            "--path", "/new/edit/path",
            "--no-permanent",
            "--no-only-current-directory"
        ])
        XCTAssertEqual(editCommandWithArgs.path, "/new/edit/path")
        XCTAssertFalse(editCommandWithArgs.permanent)
        XCTAssertFalse(editCommandWithArgs.onlyCurrentDirectory)
    }
    
    func testGenerateCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.generatePath.rawValue] = "/path/to/generate"
        mockEnvironment.tuistVariables[EnvKey.generateOpen.rawValue] = "false"
        
        let generateCommandWithEnvVars = try GenerateCommand.parse([])
        XCTAssertEqual(generateCommandWithEnvVars.path, "/path/to/generate")
        XCTAssertFalse(generateCommandWithEnvVars.open)
        
        let generateCommandWithArgs = try GenerateCommand.parse([
            "--path", "/new/generate/path",
            "--open"
        ])
        XCTAssertEqual(generateCommandWithArgs.path, "/new/generate/path")
        XCTAssertTrue(generateCommandWithArgs.open)
    }
    
    func testGraphCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.graphSkipTestTargets.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.graphSkipExternalDependencies.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.graphPlatform.rawValue] = "ios"
        mockEnvironment.tuistVariables[EnvKey.graphFormat.rawValue] = "svg"
        mockEnvironment.tuistVariables[EnvKey.graphOpen.rawValue] = "false"
        mockEnvironment.tuistVariables[EnvKey.graphLayoutAlgorithm.rawValue] = "circo"
        mockEnvironment.tuistVariables[EnvKey.graphTargets.rawValue] = "Target1,Target2"
        mockEnvironment.tuistVariables[EnvKey.graphPath.rawValue] = "/path/to/graph"
        mockEnvironment.tuistVariables[EnvKey.graphOutputPath.rawValue] = "/path/to/output"
        
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
            "--output-path", "/new/graph/output"
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
        mockEnvironment.tuistVariables[EnvKey.initPlatform.rawValue] = "macos"
        mockEnvironment.tuistVariables[EnvKey.initName.rawValue] = "MyProject"
        mockEnvironment.tuistVariables[EnvKey.initTemplate.rawValue] = "MyTemplate"
        mockEnvironment.tuistVariables[EnvKey.initPath.rawValue] = "/path/to/init"
        
        let initCommandWithEnvVars = try InitCommand.parse([])
        XCTAssertEqual(initCommandWithEnvVars.name, "MyProject")
        XCTAssertEqual(initCommandWithEnvVars.template, "MyTemplate")
        XCTAssertEqual(initCommandWithEnvVars.path, "/path/to/init")
        
        let initCommandWithArgs = try InitCommand.parse([
            "--platform", "ios",
            "--name", "NewProject",
            "--template", "NewTemplate",
            "--path", "/new/init/path"
        ])
        XCTAssertEqual(initCommandWithArgs.name, "NewProject")
        XCTAssertEqual(initCommandWithArgs.template, "NewTemplate")
        XCTAssertEqual(initCommandWithArgs.path, "/new/init/path")
    }
    
    func testInstallCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.installPath.rawValue] = "/path/to/install"
        mockEnvironment.tuistVariables[EnvKey.installUpdate.rawValue] = "true"
        
        let installCommandWithEnvVars = try InstallCommand.parse([])
        XCTAssertEqual(installCommandWithEnvVars.path, "/path/to/install")
        XCTAssertTrue(installCommandWithEnvVars.update)
        
        let installCommandWithArgs = try InstallCommand.parse([
            "--path", "/new/install/path",
            "--no-update"
        ])
        XCTAssertEqual(installCommandWithArgs.path, "/new/install/path")
        XCTAssertFalse(installCommandWithArgs.update)
    }
    
    func testListCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.scaffoldListJson.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.scaffoldListPath.rawValue] = "/path/to/list"
        
        let listCommandWithEnvVars = try ListCommand.parse([])
        XCTAssertTrue(listCommandWithEnvVars.json)
        XCTAssertEqual(listCommandWithEnvVars.path, "/path/to/list")
        
        let listCommandWithArgs = try ListCommand.parse([
            "--no-json",
            "--path", "/new/list/path"
        ])
        XCTAssertFalse(listCommandWithArgs.json)
        XCTAssertEqual(listCommandWithArgs.path, "/new/list/path")
    }
    
    func testMigrationCheckEmptyBuildSettingsCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.migrationCheckEmptySettingsXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        mockEnvironment.tuistVariables[EnvKey.migrationCheckEmptySettingsTarget.rawValue] = "MyTarget"
        
        let migrationCommandWithEnvVars = try MigrationCheckEmptyBuildSettingsCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommandWithEnvVars.target, "MyTarget")
        
        let migrationCommandWithArgs = try MigrationCheckEmptyBuildSettingsCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--target", "NewTarget"
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommandWithArgs.target, "NewTarget")
    }
    
    func testMigrationSettingsToXCConfigCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigXcconfigPath.rawValue] = "/path/to/xcconfig"
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigTarget.rawValue] = "MyTarget"
        
        let migrationCommandWithEnvVars = try MigrationSettingsToXCConfigCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommandWithEnvVars.xcconfigPath, "/path/to/xcconfig")
        XCTAssertEqual(migrationCommandWithEnvVars.target, "MyTarget")
        
        let migrationCommandWithArgs = try MigrationSettingsToXCConfigCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path",
            "--xcconfig-path", "/new/xcconfig/path",
            "--target", "NewTarget"
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommandWithArgs.xcconfigPath, "/new/xcconfig/path")
        XCTAssertEqual(migrationCommandWithArgs.target, "NewTarget")
    }
    
    func testMigrationTargetsByDependenciesCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.migrationListTargetsXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        
        let migrationCommandWithEnvVars = try MigrationTargetsByDependenciesCommand.parse([])
        XCTAssertEqual(migrationCommandWithEnvVars.xcodeprojPath, "/path/to/xcodeproj")
        
        let migrationCommandWithArgs = try MigrationTargetsByDependenciesCommand.parse([
            "--xcodeproj-path", "/new/xcodeproj/path"
        ])
        XCTAssertEqual(migrationCommandWithArgs.xcodeprojPath, "/new/xcodeproj/path")
    }
    
    func testPluginArchiveCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.pluginArchivePath.rawValue] = "/path/to/plugin"
        
        let pluginCommandWithEnvVars = try PluginArchiveCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.path, "/path/to/plugin")
        
        let pluginCommandWithArgs = try PluginArchiveCommand.parse([
            "--path", "/new/plugin/path"
        ])
        XCTAssertEqual(pluginCommandWithArgs.path, "/new/plugin/path")
    }
    
    func testPluginBuildCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsPath.rawValue] = "/path/to/plugin"
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsConfiguration.rawValue] = "debug"
        mockEnvironment.tuistVariables[EnvKey.pluginBuildBuildTests.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.pluginBuildShowBinPath.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.pluginBuildTargets.rawValue] = "Target1,Target2"
        mockEnvironment.tuistVariables[EnvKey.pluginBuildProducts.rawValue] = "Product1,Product2"
        
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
            "--products", "Product3", "--products", "Product4"
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertFalse(pluginCommandWithArgs.showBinPath)
        XCTAssertEqual(pluginCommandWithArgs.targets, ["Target3", "Target4"])
        XCTAssertEqual(pluginCommandWithArgs.products, ["Product3", "Product4"])
    }
    
    func testPluginRunCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsPath.rawValue] = "/path/to/plugin"
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsConfiguration.rawValue] = "debug"
        mockEnvironment.tuistVariables[EnvKey.pluginRunBuildTests.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.pluginRunSkipBuild.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.pluginRunTask.rawValue] = "myTask"
        mockEnvironment.tuistVariables[EnvKey.pluginRunArguments.rawValue] = "arg1,arg2,arg3"
        
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
            "arg4", "arg5"
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertFalse(pluginCommandWithArgs.skipBuild)
        XCTAssertEqual(pluginCommandWithArgs.task, "otherTask")
        XCTAssertEqual(pluginCommandWithArgs.arguments, ["arg4", "arg5"])
    }
    
    func testPluginTestCommandUsesEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsPath.rawValue] = "/path/to/plugin"
        mockEnvironment.tuistVariables[EnvKey.pluginOptionsConfiguration.rawValue] = "debug"
        mockEnvironment.tuistVariables[EnvKey.pluginTestBuildTests.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.pluginTestTestProducts.rawValue] = "Product1,Product2"
        
        let pluginCommandWithEnvVars = try PluginTestCommand.parse([])
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.path, "/path/to/plugin")
        XCTAssertEqual(pluginCommandWithEnvVars.pluginOptions.configuration, .debug)
        XCTAssertTrue(pluginCommandWithEnvVars.buildTests)
        XCTAssertEqual(pluginCommandWithEnvVars.testProducts, ["Product1", "Product2"])
        
        let pluginCommandWithArgs = try PluginTestCommand.parse([
            "--path", "/new/plugin/path",
            "--configuration", "release",
            "--no-build-tests",
            "--test-products", "Product3", "--test-products", "Product4"
        ])
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.path, "/new/plugin/path")
        XCTAssertEqual(pluginCommandWithArgs.pluginOptions.configuration, .release)
        XCTAssertFalse(pluginCommandWithArgs.buildTests)
        XCTAssertEqual(pluginCommandWithArgs.testProducts, ["Product3", "Product4"])
    }
    
    
    func testRunCommandUsesEnvVars() throws {
        // Set environment variables for RunCommand
        mockEnvironment.tuistVariables[EnvKey.runGenerate.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.runClean.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.runOS.rawValue] = "14.5"
        mockEnvironment.tuistVariables[EnvKey.runScheme.rawValue] = "MyScheme"
        mockEnvironment.tuistVariables[EnvKey.runArguments.rawValue] = "arg1,arg2,arg3"
        
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
            "arg4", "arg5"
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
        mockEnvironment.tuistVariables[EnvKey.scaffoldJson.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.scaffoldPath.rawValue] = "/path/to/scaffold"
        mockEnvironment.tuistVariables[EnvKey.scaffoldTemplate.rawValue] = "MyTemplate"
        
        // Execute ScaffoldCommand without command line arguments
        let scaffoldCommandWithEnvVars = try ScaffoldCommand.parse([])
        XCTAssertTrue(scaffoldCommandWithEnvVars.json)
        XCTAssertEqual(scaffoldCommandWithEnvVars.path, "/path/to/scaffold")
        XCTAssertEqual(scaffoldCommandWithEnvVars.template, "MyTemplate")
        
        // Execute ScaffoldCommand with command line arguments
        let scaffoldCommandWithArgs = try ScaffoldCommand.parse([
            "--no-json",
            "--path", "/new/scaffold/path",
            "AnotherTemplate"
        ])
        XCTAssertFalse(scaffoldCommandWithArgs.json)
        XCTAssertEqual(scaffoldCommandWithArgs.path, "/new/scaffold/path")
        XCTAssertEqual(scaffoldCommandWithArgs.template, "AnotherTemplate")
    }
    
    func testTestCommandWithEnvVars() throws {
        // Set environment variables for TestCommand
        mockEnvironment.tuistVariables[EnvKey.testScheme.rawValue] = "MyScheme"
        mockEnvironment.tuistVariables[EnvKey.testClean.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.testPath.rawValue] = "/path/to/test"
        mockEnvironment.tuistVariables[EnvKey.testDevice.rawValue] = "iPhone"
        mockEnvironment.tuistVariables[EnvKey.testPlatform.rawValue] = "iOS"
        mockEnvironment.tuistVariables[EnvKey.testOS.rawValue] = "14.5"
        mockEnvironment.tuistVariables[EnvKey.testRosetta.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.testConfiguration.rawValue] = "Debug"
        mockEnvironment.tuistVariables[EnvKey.testSkipUITests.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.testResultBundlePath.rawValue] = "/path/to/resultBundle"
        mockEnvironment.tuistVariables[EnvKey.testDerivedDataPath.rawValue] = "/path/to/derivedData"
        mockEnvironment.tuistVariables[EnvKey.testRetryCount.rawValue] = "2"
        mockEnvironment.tuistVariables[EnvKey.testTestPlan.rawValue] = "MyTestPlan"
//        mockEnvironment.tuistVariables[EnvKey.testTestTargets.rawValue] = "TestTarget1,TestTarget2"
        mockEnvironment.tuistVariables[EnvKey.testSkipTestTargets.rawValue] = "SkipTarget1,SkipTarget2"
        mockEnvironment.tuistVariables[EnvKey.testConfigurations.rawValue] = "Config1,Config2"
        mockEnvironment.tuistVariables[EnvKey.testSkipConfigurations.rawValue] = "SkipConfig1,SkipConfig2"
        mockEnvironment.tuistVariables[EnvKey.testGenerateOnly.rawValue] = "true"
        
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
            try TestIdentifier(string: "SkipTarget2")
        ])
        XCTAssertEqual(testCommandWithEnvVars.configurations, ["Config1", "Config2"])
        XCTAssertEqual(testCommandWithEnvVars.skipConfigurations, ["SkipConfig1", "SkipConfig2"])
        XCTAssertTrue(testCommandWithEnvVars.generateOnly)
        
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
            "--no-generate-only"
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
            try TestIdentifier(string: "NewSkipTarget2")
        ])
        XCTAssertEqual(testCommandWithArgs.configurations, ["NewConfig1", "NewConfig2"])
        XCTAssertEqual(testCommandWithArgs.skipConfigurations, ["NewSkipConfig1", "NewSkipConfig2"])
        XCTAssertFalse(testCommandWithArgs.generateOnly)
    }
}
