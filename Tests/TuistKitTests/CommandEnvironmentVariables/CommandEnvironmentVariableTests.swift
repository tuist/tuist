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
        // TODO: Implement test for CleanCommand
    }
    
    func testDumpCommandWithEnvVars() throws {
        // TODO: Implement test for DumpCommand
    }
    
    func testEditCommandWithEnvVars() throws {
        // TODO: Implement test for EditCommand
    }
    
    func testGenerateCommandWithEnvVars() throws {
        // TODO: Implement test for GenerateCommand
    }
    
    func testGraphCommandWithEnvVars() throws {
        // TODO: Implement test for GraphCommand
    }
    
    func testInitCommandWithEnvVars() throws {
        // TODO: Implement test for InitCommand
    }
    
    func testInstallCommandWithEnvVars() throws {
        // TODO: Implement test for InstallCommand
    }
    
    func testListCommandWithEnvVars() throws {
        // TODO: Implement test for ListCommand
    }
    
    func testMigrationCheckEmptyBuildSettingsCommandWithEnvVars() throws {
        // TODO: Implement test for MigrationCheckEmptyBuildSettingsCommand
    }
    
    func testMigrationSettingsToXCConfigCommandWithEnvVars() throws {
        // TODO: Implement test for MigrationSettingsToXCConfigCommand
    }
    
    func testMigrationTargetsByDependenciesCommandWithEnvVars() throws {
        // TODO: Implement test for MigrationTargetsByDependenciesCommand
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
