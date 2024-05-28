@testable import ArgumentParser
import Difference
import Foundation
import TSCBasic
import XCTest
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
    
    func testBuildCommandWithEnvVars() throws {
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_SCHEMES"] = "Scheme1,Scheme2"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_GENERATE"] = "true"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_CLEAN"] = "true"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_PATH"] = "/path/to/project"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_DEVICE"] = "iPhone"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_PLATFORM"] = "ios"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_OS"] = "14.5"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_ROSETTA"] = "true"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_CONFIGURATION"] = "Debug"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_BUILD_OUTPUT_PATH"] = "/path/to/output"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_DERIVED_DATA_PATH"] = "/path/to/derivedData"
        mockEnvironment.tuistVariables["TUIST_BUILD_OPTIONS_GENERATE_ONLY"] = "true"
        
        let buildCommand1 = try BuildCommand.parse([])
        XCTAssertEqual(buildCommand1.buildOptions.schemes, ["Scheme1", "Scheme2"])
        XCTAssertTrue(buildCommand1.buildOptions.generate)
        XCTAssertTrue(buildCommand1.buildOptions.clean)
        XCTAssertEqual(buildCommand1.buildOptions.path, "/path/to/project")
        XCTAssertEqual(buildCommand1.buildOptions.device, "iPhone")
        XCTAssertEqual(buildCommand1.buildOptions.platform, .iOS)
//        XCTAssertEqual(buildCommand1.buildOptions.os?.description, "14.5")
        XCTAssertTrue(buildCommand1.buildOptions.rosetta)
        XCTAssertEqual(buildCommand1.buildOptions.configuration, "Debug")
        XCTAssertEqual(buildCommand1.buildOptions.buildOutputPath, "/path/to/output")
        XCTAssertEqual(buildCommand1.buildOptions.derivedDataPath, "/path/to/derivedData")
        XCTAssertTrue(buildCommand1.buildOptions.generateOnly)
        
        // Execute BuildCommand with command line arguments
        let buildCommand2 = try BuildCommand.parse(["Scheme3", "--generate", "--no-clean", "--path", "/new/path", "--device", "iPad", "--platform", "tvos", "--no-rosetta", "--configuration", "Release", "--build-output-path", "/new/output", "--derived-data-path", "/new/derivedData", "--no-generate-only"])
        XCTAssertEqual(buildCommand2.buildOptions.schemes, ["Scheme3"])
        XCTAssertTrue(buildCommand2.buildOptions.generate)
        XCTAssertFalse(buildCommand2.buildOptions.clean)
        XCTAssertEqual(buildCommand2.buildOptions.path, "/new/path")
        XCTAssertEqual(buildCommand2.buildOptions.device, "iPad")
        XCTAssertEqual(buildCommand2.buildOptions.platform, .tvOS)
//        XCTAssertEqual(buildCommand2.buildOptions.os?.description, "15.0")
        XCTAssertFalse(buildCommand2.buildOptions.rosetta)
        XCTAssertEqual(buildCommand2.buildOptions.configuration, "Release")
        XCTAssertEqual(buildCommand2.buildOptions.buildOutputPath, "/new/output")
        XCTAssertEqual(buildCommand2.buildOptions.derivedDataPath, "/new/derivedData")
        XCTAssertFalse(buildCommand2.buildOptions.generateOnly)
    }
    
    func testCleanCommandWithEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.cleanCleanCategories.rawValue] = "category1,category2"
        mockEnvironment.tuistVariables[EnvKey.cleanPath.rawValue] = "/path/to/clean"
        
    }
    
    func testDumpCommandWithEnvVars() throws {
        // TODO: Implement test for DumpCommand
    }
    
    func testEditCommandWithEnvVars() throws {
        mockEnvironment.tuistVariables[EnvKey.editPath.rawValue] = "/path/to/edit"
        mockEnvironment.tuistVariables[EnvKey.editPermanent.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.editOnlyCurrentDirectory.rawValue] = "true"
        
        let editCommand1 = try EditCommand.parse([])
        XCTAssertEqual(editCommand1.path, "/path/to/edit")
        XCTAssertTrue(editCommand1.permanent)
        XCTAssertTrue(editCommand1.onlyCurrentDirectory)
        
        let editCommand2 = try EditCommand.parse(["--path", "/new/edit/path", "--no-permanent", "--no-only-current-directory"])
        XCTAssertEqual(editCommand2.path, "/new/edit/path")
        XCTAssertFalse(editCommand2.permanent)
        XCTAssertFalse(editCommand2.onlyCurrentDirectory)
    }

    
    func testGenerateCommandWithEnvVars() throws {
        // Set environment variables for Generate command
        mockEnvironment.tuistVariables[EnvKey.generatePath.rawValue] = "/path/to/generate"
        mockEnvironment.tuistVariables[EnvKey.generateOpen.rawValue] = "false"
        
        let generateCommand1 = try GenerateCommand.parse([])
        XCTAssertEqual(generateCommand1.path, "/path/to/generate")
        print(generateCommand1.open)
        XCTAssertFalse(generateCommand1.open)
        
        let generateCommand2 = try GenerateCommand.parse(["--path", "/new/generate/path", "--open"])
        XCTAssertEqual(generateCommand2.path, "/new/generate/path")
        XCTAssertTrue(generateCommand2.open)
    }

    
    func testGraphCommandWithEnvVars() throws {
        // Set environment variables for Graph command
        mockEnvironment.tuistVariables[EnvKey.graphSkipTestTargets.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.graphSkipExternalDependencies.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.graphPlatform.rawValue] = "ios"
        mockEnvironment.tuistVariables[EnvKey.graphFormat.rawValue] = "svg"
        mockEnvironment.tuistVariables[EnvKey.graphOpen.rawValue] = "false"
        mockEnvironment.tuistVariables[EnvKey.graphLayoutAlgorithm.rawValue] = "circo"
        mockEnvironment.tuistVariables[EnvKey.graphTargets.rawValue] = "Target1,Target2"
        mockEnvironment.tuistVariables[EnvKey.graphPath.rawValue] = "/path/to/graph"
        mockEnvironment.tuistVariables[EnvKey.graphOutputPath.rawValue] = "/path/to/output"
        
        // Execute GraphCommand without command line arguments
        let graphCommand1 = try GraphCommand.parse([])
        XCTAssertTrue(graphCommand1.skipTestTargets)
        XCTAssertTrue(graphCommand1.skipExternalDependencies)
        XCTAssertEqual(graphCommand1.platform, .iOS)
        XCTAssertEqual(graphCommand1.format, .svg)
        XCTAssertFalse(graphCommand1.open)
        XCTAssertEqual(graphCommand1.layoutAlgorithm, .circo)
        XCTAssertEqual(graphCommand1.targets, ["Target1", "Target2"])
        XCTAssertEqual(graphCommand1.path, "/path/to/graph")
        XCTAssertEqual(graphCommand1.outputPath, "/path/to/output")
        
        // Execute GraphCommand with command line arguments
        let graphCommand2 = try GraphCommand.parse(["--no-skip-test-targets", "--no-skip-external-dependencies", "--platform", "macos", "--format", "json", "--open", "--algorithm", "fdp", "Target3", "Target4", "--path", "/new/graph/path", "--output-path", "/new/graph/output"])
        XCTAssertFalse(graphCommand2.skipTestTargets)
        XCTAssertFalse(graphCommand2.skipExternalDependencies)
        XCTAssertEqual(graphCommand2.platform, .macOS)
        XCTAssertEqual(graphCommand2.format, .json)
        XCTAssertTrue(graphCommand2.open)
        XCTAssertEqual(graphCommand2.layoutAlgorithm, .fdp)
        XCTAssertEqual(graphCommand2.targets, ["Target3", "Target4"])
        XCTAssertEqual(graphCommand2.path, "/new/graph/path")
        XCTAssertEqual(graphCommand2.outputPath, "/new/graph/output")
    }

    
    func testInitCommandWithEnvVars() throws {
        // Set environment variables for Init command
        mockEnvironment.tuistVariables[EnvKey.initPlatform.rawValue] = "macos"
        mockEnvironment.tuistVariables[EnvKey.initName.rawValue] = "MyProject"
        mockEnvironment.tuistVariables[EnvKey.initTemplate.rawValue] = "MyTemplate"
        mockEnvironment.tuistVariables[EnvKey.initPath.rawValue] = "/path/to/init"
        
        // Execute InitCommand without command line arguments
        let initCommand1 = try InitCommand.parse([])
//        XCTAssertEqual(initCommand1.platform, Platform.IOS)
        XCTAssertEqual(initCommand1.name, "MyProject")
        XCTAssertEqual(initCommand1.template, "MyTemplate")
        XCTAssertEqual(initCommand1.path, "/path/to/init")
        
        // Execute InitCommand with command line arguments
        let initCommand2 = try InitCommand.parse(["--platform", "ios", "--name", "NewProject", "--template", "NewTemplate", "--path", "/new/init/path"])
//        XCTAssertEqual(initCommand2.platform, .ios)
        XCTAssertEqual(initCommand2.name, "NewProject")
        XCTAssertEqual(initCommand2.template, "NewTemplate")
        XCTAssertEqual(initCommand2.path, "/new/init/path")
    }

    func testInstallCommandWithEnvVars() throws {
        // Set environment variables for Install command
        mockEnvironment.tuistVariables[EnvKey.installPath.rawValue] = "/path/to/install"
        mockEnvironment.tuistVariables[EnvKey.installUpdate.rawValue] = "true"
        
        // Execute InstallCommand without command line arguments
        let installCommand1 = try InstallCommand.parse([])
        XCTAssertEqual(installCommand1.path, "/path/to/install")
        XCTAssertTrue(installCommand1.update)
        
        // Execute InstallCommand with command line arguments
        let installCommand2 = try InstallCommand.parse(["--path", "/new/install/path", "--no-update"])
        XCTAssertEqual(installCommand2.path, "/new/install/path")
        XCTAssertFalse(installCommand2.update)
    }

    func testListCommandWithEnvVars() throws {
        // Set environment variables for List command
        mockEnvironment.tuistVariables[EnvKey.scaffoldListJson.rawValue] = "true"
        mockEnvironment.tuistVariables[EnvKey.scaffoldListPath.rawValue] = "/path/to/list"
        
        // Execute ListCommand without command line arguments
        let listCommand1 = try ListCommand.parse([])
        XCTAssertTrue(listCommand1.json)
        XCTAssertEqual(listCommand1.path, "/path/to/list")
        
        // Execute ListCommand with command line arguments
        let listCommand2 = try ListCommand.parse(["--no-json", "--path", "/new/list/path"])
        XCTAssertFalse(listCommand2.json)
        XCTAssertEqual(listCommand2.path, "/new/list/path")
    }

    
    func testMigrationCheckEmptyBuildSettingsCommandWithEnvVars() throws {
        // Set environment variables for MigrationCheckEmptyBuildSettingsCommand
        mockEnvironment.tuistVariables[EnvKey.migrationCheckEmptySettingsXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        mockEnvironment.tuistVariables[EnvKey.migrationCheckEmptySettingsTarget.rawValue] = "MyTarget"
        
        // Execute MigrationCheckEmptyBuildSettingsCommand without command line arguments
        let migrationCommand1 = try MigrationCheckEmptyBuildSettingsCommand.parse([])
        XCTAssertEqual(migrationCommand1.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommand1.target, "MyTarget")
        
        // Execute MigrationCheckEmptyBuildSettingsCommand with command line arguments
        let migrationCommand2 = try MigrationCheckEmptyBuildSettingsCommand.parse(["--xcodeproj-path", "/new/xcodeproj/path", "--target", "NewTarget"])
        XCTAssertEqual(migrationCommand2.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommand2.target, "NewTarget")
    }

    func testMigrationSettingsToXCConfigCommandWithEnvVars() throws {
        // Set environment variables for MigrationSettingsToXCConfigCommand
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigXcconfigPath.rawValue] = "/path/to/xcconfig"
        mockEnvironment.tuistVariables[EnvKey.migrationSettingsToXcconfigTarget.rawValue] = "MyTarget"
        
        // Execute MigrationSettingsToXCConfigCommand without command line arguments
        let migrationCommand1 = try MigrationSettingsToXCConfigCommand.parse([])
        XCTAssertEqual(migrationCommand1.xcodeprojPath, "/path/to/xcodeproj")
        XCTAssertEqual(migrationCommand1.xcconfigPath, "/path/to/xcconfig")
        XCTAssertEqual(migrationCommand1.target, "MyTarget")
        
        // Execute MigrationSettingsToXCConfigCommand with command line arguments
        let migrationCommand2 = try MigrationSettingsToXCConfigCommand.parse(["--xcodeproj-path", "/new/xcodeproj/path", "--xcconfig-path", "/new/xcconfig/path", "--target", "NewTarget"])
        XCTAssertEqual(migrationCommand2.xcodeprojPath, "/new/xcodeproj/path")
        XCTAssertEqual(migrationCommand2.xcconfigPath, "/new/xcconfig/path")
        XCTAssertEqual(migrationCommand2.target, "NewTarget")
    }
    
    func testMigrationTargetsByDependenciesCommandWithEnvVars() throws {
        // Set environment variables for MigrationTargetsByDependenciesCommand
        mockEnvironment.tuistVariables[EnvKey.migrationListTargetsXcodeprojPath.rawValue] = "/path/to/xcodeproj"
        
        // Execute MigrationTargetsByDependenciesCommand without command line arguments
        let migrationCommand1 = try MigrationTargetsByDependenciesCommand.parse([])
        XCTAssertEqual(migrationCommand1.xcodeprojPath, "/path/to/xcodeproj")
        
        // Execute MigrationTargetsByDependenciesCommand with command line arguments
        let migrationCommand2 = try MigrationTargetsByDependenciesCommand.parse(["--xcodeproj-path", "/new/xcodeproj/path"])
        XCTAssertEqual(migrationCommand2.xcodeprojPath, "/new/xcodeproj/path")
    }
    
    func testPluginArchiveCommandWithEnvVars() throws {
        // TODO: Implement test for PluginArchiveCommand
    }
    
    func testPluginBuildCommandWithEnvVars() throws {
        // TODO: Implement test for PluginBuildCommand
    }
    
    func testPluginRunCommandWithEnvVars() throws {
        // TODO: Implement test for PluginRunCommand
    }
    
    func testPluginTestCommandWithEnvVars() throws {
        // TODO: Implement test for PluginTestCommand
    }
    
    func testRunCommandWithEnvVars() throws {
        // TODO: Implement test for RunCommand
    }
    
    func testScaffoldCommandWithEnvVars() throws {
        // TODO: Implement test for ScaffoldCommand
    }
    
    func testTestCommandWithEnvVars() throws {
        // TODO: Implement test for TestCommand
    }
}
