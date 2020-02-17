import Basic
import Foundation
import TuistCore
import TuistSupport

enum XCFrameworkBuilderError: FatalError {
    case nonFrameworkTarget(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .nonFrameworkTarget: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .nonFrameworkTarget(name):
            return "Can't generate an .xcframework from the target '\(name)' because it's not a framework target"
        }
    }
}

public protocol XCFrameworkBuilding {
    /// It builds an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - workspacePath: Path to the generated .xcworkspace that contains the given target.
    ///   - target: Target whose .xcframework will be generated.
    /// - Returns: Path to the compiled .xcframework.
    func build(workspacePath: AbsolutePath, target: Target) throws -> AbsolutePath

    /// It builds an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the generated .xcodeproj that contains the given target.
    ///   - target: Target whose .xcframework will be generated.
    /// - Returns: Path to the compiled .xcframework.
    func build(projectPath: AbsolutePath, target: Target) throws -> AbsolutePath
}

public final class XCFrameworkBuilder: XCFrameworkBuilding {
    // MARK: - Attributes

    /// When true the builder outputs the output from xcodebuild.
    private let printOutput: Bool

    // MARK: - Init

    /// Initializes the builder.
    /// - Parameter printOutput: When true the builder outputs the output from xcodebuild.
    public init(printOutput: Bool = true) {
        self.printOutput = printOutput
    }

    // MARK: - XCFrameworkBuilding

    public func build(workspacePath: AbsolutePath, target: Target) throws -> AbsolutePath {
        try build(arguments: ["-workspace", workspacePath.pathString], target: target)
    }

    public func build(projectPath: AbsolutePath, target: Target) throws -> AbsolutePath {
        try build(arguments: ["-project", projectPath.pathString], target: target)
    }

    // MARK: - Fileprivate

    fileprivate func build(arguments: [String], target: Target) throws -> AbsolutePath {
        if target.product != .framework {
            throw XCFrameworkBuilderError.nonFrameworkTarget(target.name)
        }

        // Create temporary directories
        let outputDirectory = try TemporaryDirectory(removeTreeOnDeinit: false)
        let derivedDataPath = try TemporaryDirectory(removeTreeOnDeinit: true)

        Printer.shared.print(section: "Building .xcframework for \(target.name)")

        // Build for the device
        let deviceArchivePath = derivedDataPath.path.appending(component: "device.xcarchive")
        var deviceArguments = xcodebuildCommand(scheme: target.name,
                                                destination: deviceDestination(platform: target.platform),
                                                sdk: target.platform.xcodeDeviceSDK,
                                                derivedDataPath: derivedDataPath.path)
        deviceArguments.append(contentsOf: ["-archivePath", deviceArchivePath.pathString])
        deviceArguments.append(contentsOf: arguments)
        Printer.shared.print(subsection: "Building \(target.name) for device")
        try runCommand(deviceArguments)

        // Build for the simulator
        var simulatorArchivePath: AbsolutePath?
        if target.platform.hasSimulators {
            simulatorArchivePath = derivedDataPath.path.appending(component: "simulator.xcarchive")
            var simulatorArguments = xcodebuildCommand(scheme: target.name,
                                                       destination: target.platform.xcodeSimulatorDestination!,
                                                       sdk: target.platform.xcodeSimulatorSDK!,
                                                       derivedDataPath: derivedDataPath.path)
            simulatorArguments.append(contentsOf: ["-archivePath", simulatorArchivePath!.pathString])
            simulatorArguments.append(contentsOf: arguments)
            Printer.shared.print(subsection: "Building \(target.name) for simulator")
            try runCommand(simulatorArguments)
        }

        // Build the xcframework
        Printer.shared.print(subsection: "Exporting xcframework for \(target.name)")
        let xcframeworkPath = outputDirectory.path.appending(component: "\(target.productName).xcframework")
        let xcframeworkArguments = xcodebuildXcframeworkCommand(deviceArchivePath: deviceArchivePath,
                                                                simulatorArchivePath: simulatorArchivePath,
                                                                productName: target.productName,
                                                                xcframeworkPath: xcframeworkPath)
        try runCommand(xcframeworkArguments)

        return xcframeworkPath
    }

    /// Runs the given command.
    /// - Parameter arguments: Command arguments.
    fileprivate func runCommand(_ arguments: [String]) throws {
        if printOutput {
            try System.shared.runAndPrint(arguments)
        } else {
            try System.shared.run(arguments)
        }
    }

    /// Returns the arguments that should be passed to xcodebuild to compile for a device on the given platform.
    /// - Parameter platform: Platform we are compiling for.
    fileprivate func deviceDestination(platform: Platform) -> String {
        switch platform {
        case .macOS: return "osx"
        default: return "generic/platform=\(platform.caseValue)"
        }
    }

    /// Returns the xcodebuild command to generate the .xcframework from the device
    /// and the simulator frameworks.
    ///
    /// - Parameters:
    ///   - deviceArchivePath: Path to the archive that contains the framework for the device.
    ///   - simulatorArchivePath: Path to the archive that contains the framework for the simulator.
    ///   - productName: Name of the product.
    ///   - xcframeworkPath: Path where the .xcframework should be exported to (e.g. /path/to/MyFeature.xcframework).
    fileprivate func xcodebuildXcframeworkCommand(deviceArchivePath: AbsolutePath,
                                                  simulatorArchivePath: AbsolutePath?,
                                                  productName: String,
                                                  xcframeworkPath: AbsolutePath) -> [String] {
        var command = ["xcrun", "xcodebuild", "-create-xcframework"]
        command.append(contentsOf: ["-framework", deviceArchivePath.appending(RelativePath("Products/Library/Frameworks/\(productName).framework")).pathString])
        if let simulatorArchivePath = simulatorArchivePath {
            command.append(contentsOf: ["-framework", simulatorArchivePath.appending(RelativePath("Products/Library/Frameworks/\(productName).framework")).pathString])
        }
        command.append(contentsOf: ["-output", xcframeworkPath.pathString])
        return command
    }

    /// It returns the xcodebuild command to archive the .framework.
    /// - Parameters:
    ///   - scheme: Name of the scheme that archives the framework.
    ///   - destination: Compilation destination.
    ///   - sdk: Compilation SDK.
    ///   - derivedDataPath: Derived data directory.
    fileprivate func xcodebuildCommand(scheme: String, destination: String, sdk: String, derivedDataPath: AbsolutePath) -> [String] {
        var command = ["xcrun", "xcodebuild", "archive"]
        command.append(contentsOf: ["-scheme", scheme.spm_shellEscaped()])
        command.append(contentsOf: ["-sdk", sdk])
        command.append(contentsOf: ["-destination='\(destination)'"])
        command.append(contentsOf: ["-derivedDataPath", derivedDataPath.pathString])
        // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
        command.append(contentsOf: ["SKIP_INSTALL=NO", "BUILD_LIBRARY_FOR_DISTRIBUTION=YES"])
        return command
    }
}
