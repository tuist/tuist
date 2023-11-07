// swiftlint:disable force_try
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupportTesting
import XCTest

@testable import TuistKit
@testable import TuistSupport

public enum Destination {
    case simulator, device
}

let cacheDirectory = try! TemporaryDirectory(removeTreeOnDeinit: true).path
var usedDevices: Set<String> = []
var counter = 0

open class TuistAcceptanceTestCase: TuistTestCase {
    public var xcodeprojPath: AbsolutePath!
    public var workspacePath: AbsolutePath!
    public var fixturePath: AbsolutePath!
    public var derivedDataPath: AbsolutePath!

    private var sourceRootPath: AbsolutePath!
    private var testingDevices: [Platform: String] = [:]

    override open func setUp() {
        super.setUp()

        derivedDataPath = try! TemporaryDirectory(removeTreeOnDeinit: true).path
        setenv(
            Constants.EnvironmentVariables.forceConfigCacheDirectory,
            cacheDirectory.pathString,
            1
        )

        sourceRootPath = try! AbsolutePath(
            validating: ProcessInfo.processInfo.environment[
                "TUIST_CONFIG_SRCROOT"
            ]!
        )
        environment.tuistConfigVariables[
            Constants.EnvironmentVariables.xcbeautifyBinaryPath
        ] = sourceRootPath
            .appending(components: ["vendor", ".build", "debug", "xcbeautify"])
            .pathString

        DeveloperEnvironment.shared = DeveloperEnvironment()
    }

    
    open override func tearDown() async throws {
        xcodeprojPath = nil
        workspacePath = nil
        fixturePath = nil
        derivedDataPath = nil
        
        try testingDevices.values.forEach { try System.shared.run(["/usr/bin/xcrun", "simctl", "delete", $0]) }
        testingDevices = [:]
        try await super.tearDown()
    }

    public func setUpFixture(_ fixture: String) throws {
        let fixturesPath = sourceRootPath
            .appending(component: "fixtures")

        fixturePath = FileHandler.shared.currentPath.appending(component: fixture)

        try FileHandler.shared.copy(
            from: fixturesPath.appending(component: fixture),
            to: fixturePath
        )

        try poisonCache()
    }

    /// We need to poison the cache when we start a given test as we share
    private func poisonCache() throws {
        let filePath = try XCTUnwrap(FileHandler.shared.glob(fixturePath, glob: "**/*.swift").first)
        var contents = try FileHandler.shared.readTextFile(filePath)
        contents += "\n"
        try FileHandler.shared.write(contents, path: filePath, atomically: true)
    }

    public func run(_ command: (some AsyncParsableCommand).Type, _ arguments: [String] = []) async throws {
        var arguments = arguments

        if String(describing: command) == "GenerateCommand" {
            arguments.append("--no-open")
        }

        if String(describing: command) == "TestCommand"
            || String(describing: command) == "BuildCommand"
        {
            arguments.append(contentsOf: ["--derived-data-path", derivedDataPath.pathString])
        }

        let platform = Platform.allCases
            .first(where: { arguments.joined().contains($0.caseValue) }) ?? .iOS
        if String(describing: command) == "TestCommand", platform != .macOS {
            let testingDevice: String
            if let testingDeviceName = testingDevices[platform] {
                testingDevice = testingDeviceName
            } else {
                let devices = try await SimulatorController().findAvailableDevices(
                    platform: platform,
                    version: nil,
                    minVersion: nil,
                    deviceName: nil
                )
                let device = try XCTUnwrap(
                    devices.first(
                        where: { $0.device.isShutdown && !$0.device.name.contains("tuist-testing-device") }
                    )
                )
                let testingDeviceName = "tuist-testing-device-\(UUID().uuidString)"
                testingDevices[platform] = testingDeviceName
                try System.shared.run(["/usr/bin/xcrun", "simctl", "clone", device.device.name, testingDeviceName])
                testingDevice = testingDeviceName
            }
            arguments.append(contentsOf: ["--device", testingDevice])
        }

        var parsedCommand = try command.parse(
            arguments +
                ["--path", fixturePath.pathString]
        )
        try await parsedCommand.run()

        if String(describing: command) == "GenerateCommand" {
            xcodeprojPath = try FileHandler.shared.contentsOfDirectory(fixturePath)
                .first(where: { $0.extension == "xcodeproj" })
            workspacePath = try FileHandler.shared.contentsOfDirectory(fixturePath)
                .first(where: { $0.extension == "xcworkspace" })
        }
    }

    public func run(_ command: (some AsyncParsableCommand).Type, _ arguments: String...) async throws {
        try await run(command, Array(arguments))
    }

    public func run(_ command: (some ParsableCommand).Type, _ arguments: [String] = []) throws {
        if String(describing: command) == "InitCommand" {
            fixturePath = FileHandler.shared.currentPath.appending(
                component: arguments[arguments.firstIndex(where: { $0 == "--name" })! + 1]
            )
        }
        var parsedCommand = try command.parseAsRoot(
            arguments +
                ["--path", fixturePath.pathString]
        )
        try parsedCommand.run()

        if command == InitCommand.self {
            try poisonCache()
        }
    }

    public func run(_ command: (some ParsableCommand).Type, _ arguments: String...) throws {
        try run(command, Array(arguments))
    }

    public func addEmptyLine(to file: String) throws {
        let filePath = try fixturePath.appending(RelativePath(validating: file))
        var contents = try FileHandler.shared.readTextFile(filePath)
        contents += "\n"
        try FileHandler.shared.write(contents, path: filePath, atomically: true)
    }
}

// swiftlint:enable force_try
