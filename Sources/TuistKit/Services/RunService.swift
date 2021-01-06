import Foundation
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistSupport

enum RunServiceError: FatalError {
    case appNotFound(targetName: String)
    case platformNotSupported(platformName: String)
    case schemeNotFound(schemeName: String, buildableSchemes: [String])
    case targetNotFound(schemeName: String)

    var description: String {
        switch self {
        case let .appNotFound(targetName):
            return "Couldn't find any apps build for \(targetName)"
        case let .platformNotSupported(platformName):
            return "The Run command does not support \(platformName)"
        case let .schemeNotFound(schemeName, buildableSchemes):
            return "\(schemeName) could not be found, but here are the available schemes: \(buildableSchemes)"
        case let .targetNotFound(schemeName):
            return "Couldn't find \(schemeName)"
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
    let generator: Generating
    let xcodeBuildController: XcodeBuildControlling
    var appPath: AbsolutePath?
    var buildableTarget: Target?

    init(simulatorController: SimulatorControlling = SimulatorController(),
         buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
         generator: Generating = Generator(contentHasher: CacheContentHasher()),
         xcodeBuildController: XcodeBuildControlling = XcodeBuildController())
    {
        self.simulatorController = simulatorController
        self.buildGraphInspector = buildGraphInspector
        self.generator = generator
        self.xcodeBuildController = xcodeBuildController
    }

    func run(schemeName: String) throws {
        _ = try Observable.combineLatest(buildScheme(schemeName),
                                         findAndPrepareSimulator())
            .toBlocking()
            .last()

        _ = try simulatorController.installAppBuilt(appPath: try findApp(for: buildableTarget!))
            .toBlocking()
            .last()

        _ = try simulatorController.launchApp(bundleId: buildableTarget!.bundleId)
            .toBlocking()
            .last()
    }

    private func findAndPrepareSimulator() -> Observable<SystemEvent<Data>> {
        simulatorController.findAvailableDevice(platform: Platform(rawValue: "ios")!).asObservable()
            .flatMap { simulatorAndRunTime -> Observable<SystemEvent<Data>> in
                if simulatorAndRunTime.device.isShutdown {
                    return self.simulatorController.bootSimulator(simulatorAndRunTime)
                } else {
                    return self.simulatorController.shutdownSimulator(simulatorAndRunTime.device.udid)
                        .concat(self.simulatorController.bootSimulator(simulatorAndRunTime))
                }
            }
    }

    private func buildScheme(_ schemeName: String) -> Observable<SystemEvent<XcodeBuildOutput>> {
        do {
            let graph = try generator.load(path: FileHandler.shared.currentPath)
            let schemes = buildGraphInspector.buildableSchemes(graph: graph)
            guard let scheme = schemes.first(where: { $0.name == schemeName }) else {
                return Observable.error(RunServiceError.schemeNotFound(schemeName: schemeName, buildableSchemes: schemes.map(\.name)))
            }
            buildableTarget = buildGraphInspector.buildableTarget(scheme: scheme, graph: graph)
            let workspacePath = try buildGraphInspector.workspacePath(directory: FileHandler.shared.currentPath)!
            return xcodeBuildController.build(.workspace(workspacePath), scheme: schemeName, clean: false, arguments: buildGraphInspector.buildArguments(target: buildableTarget!, configuration: nil, skipSigning: true))
        } catch {
            return Observable.error(error)
        }
    }

    private func findApp(for target: Target) throws -> AbsolutePath {
        guard target.platform == Platform.iOS else {
            throw RunServiceError.platformNotSupported(platformName: target.platform.rawValue)
        }

        let derivedDataPath = try XcodeController.shared.derivedDataPath()
        let appLocation = FileHandler.shared.locateDirectory(derivedDataPath, traversingFrom: FileHandler.shared.currentPath)?.glob("*-*/Build/Products/Debug-\(target.platform.xcodeSimulatorSDK!)/\(target.productName).app")
        guard let locations = appLocation else { throw RunServiceError.appNotFound(targetName: target.name) }
        if locations.isEmpty {
            throw RunServiceError.appNotFound(targetName: target.name)
        } else {
            return locations.first!
        }
    }
}
