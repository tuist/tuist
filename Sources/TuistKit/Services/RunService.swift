import Foundation
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCore
import TuistSupport

enum RunServiceError: FatalError {
    case appNotFound(targetName: String)
    case platformNotSupported(platformName: String)
    case schemeNotFound(schemeName: String, buildableSchemes: [String])
    case targetNotFound(forSchemeName: String)

    var description: String {
        switch self {
        case let .appNotFound(targetName):
            return "Couldn't find any apps built for \(targetName)"
        case let .platformNotSupported(platformName):
            return "The Run command does not support \(platformName) at this time"
        case let .schemeNotFound(schemeName, buildableSchemes):
            return "\(schemeName) could not be found, but here are the available schemes: \(buildableSchemes)"
        case let .targetNotFound(forSchemeName):
            return "Couldn't find \(forSchemeName)"
        }
    }

    var type: ErrorType {
        switch self {
        case .appNotFound, .platformNotSupported, .schemeNotFound, .targetNotFound:
            return .abort
        }
    }
}

final class RunService {
    let simulatorController: SimulatorControlling
    let buildGraphInspector: BuildGraphInspecting
    let projectGenerator: ProjectGenerating
    let xcodebuildController: XcodeBuildControlling
    var appPath: AbsolutePath?
    var buildableTarget: Target?

    init(simulatorController: SimulatorControlling = SimulatorController(),
         buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
         projectGenerator: ProjectGenerating = ProjectGenerator(),
         xcodebuildController: XcodeBuildControlling = XcodeBuildController())
    {
        self.simulatorController = simulatorController
        self.buildGraphInspector = buildGraphInspector
        self.projectGenerator = projectGenerator
        self.xcodebuildController = xcodebuildController
    }

    func run(schemeName: String) throws {
        try buildScheme(schemeName)

        guard let buildableTarget = buildableTarget else {
            throw RunServiceError.targetNotFound(forSchemeName: schemeName)
        }

        appPath = try findApp(for: buildableTarget)
    }

    private func buildScheme(_ schemeName: String) throws {
        let graph = try projectGenerator.load(path: FileHandler.shared.currentPath)
        let schemes = buildGraphInspector.buildableSchemes(graph: graph)
        guard let scheme = schemes.first(where: { $0.name == schemeName }) else {
            throw RunServiceError.schemeNotFound(schemeName: schemeName, buildableSchemes: schemes.map { $0.name })
        }

        buildableTarget = buildGraphInspector.buildableTarget(scheme: scheme, graph: graph)

        let workspacePath = try buildGraphInspector.workspacePath(directory: FileHandler.shared.currentPath)!

        _ = try xcodebuildController.build(.workspace(workspacePath),
                                           scheme: schemeName,
                                           clean: false,
                                           arguments: buildGraphInspector.buildArguments(target: buildableTarget!,
                                                                                         configuration: nil))
            .printFormattedOutput()
            .toBlocking()
            .last()
    }

    private func findApp(for target: Target) throws -> AbsolutePath {
        guard target.platform == Platform.iOS else {
            throw RunServiceError.platformNotSupported(platformName: target.platform.rawValue)
        }

        let derivedDataPath = try XcodeController.shared.derivedDataPath()
        let appsLocation = FileHandler.shared.locateDirectory(String(derivedDataPath.pathString.drop { ($0 == "/") || ($0 == "~") }),
                                                              traversingFrom: FileHandler.shared.currentPath)?
            .glob("\(target.name)-*/Build/Products/Debug-\(target.platform.xcodeSimulatorSDK!)/*.app")
        guard let locations = appsLocation else { throw RunServiceError.appNotFound(targetName: target.name) }
        if locations.isEmpty {
            throw RunServiceError.appNotFound(targetName: target.name)
        } else {
            return locations.first!
        }
    }
}
