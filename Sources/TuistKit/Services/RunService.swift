import Foundation
import TuistAutomation
import TSCBasic
import TuistCore
import TuistSupport
import RxSwift

enum RunServiceError: FatalError {
    case appNotFound(targetName: String)
    case simulatorNotFound
    case targetNotFound(forSchemeName: String)
    
    var description: String {
        switch self {
        case let .appNotFound(targetName):
            return "Couldn't find any apps built for \(targetName)"
        case .simulatorNotFound:
            return "Could't find simulator"
        case let .targetNotFound(forSchemeName):
            return "Couldn't find \(forSchemeName)"
        }
    }
    
    var type: ErrorType {
        switch self {
        case .appNotFound, .simulatorNotFound, .targetNotFound:
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
         xcodebuildController: XcodeBuildControlling = XcodeBuildController()) {
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
        try launchApp(for: buildableTarget)
        
    }
    
    private func buildScheme(_ schemeName: String) throws {
        let graph = try projectGenerator.load(path: FileHandler.shared.currentPath)
        guard let scheme = buildGraphInspector.buildableSchemes(graph: graph).first(where: { $0.name == schemeName }) else {
            throw RunServiceError.appNotFound(targetName: "")
        }
        
        self.buildableTarget = buildGraphInspector.buildableTarget(scheme: scheme, graph: graph)
        
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
        let appsLocation = FileHandler.shared.locateDirectory("../Library/Developer/Xcode/DerivedData/",
                                                              traversingFrom: FileHandler.shared.currentPath)?
            .glob("\(target.name)-*")
            .first?
            .glob("Build/Products/Debug-iphonesimulator/*.app")
        
        guard let locations = appsLocation else { throw RunServiceError.appNotFound(targetName: target.name) }
        if locations.count == 0 {
            throw RunServiceError.appNotFound(targetName: target.name)
        } else {
            return locations.first!
        }
    }
    
    private func launchApp(for target: Target) throws {
        let simulator = try findDevice()
        
        if let simulator = simulator {
            if simulator.isShutdown {
                try simulatorController.bootSimulator(simulator)
            }
            try installAppBuilt(for: target)
            try launchAppOnSimulator(for: target)
        } else {
            throw RunServiceError.simulatorNotFound
        }
    }
    
    // Sort of wondering if it belongs here or in the SimulatorController class
    // At some point we can imagine we'll have some arguments to determine which
    // simulator to pick (device, OS version, etc)
    private func findDevice() throws -> SimulatorDevice? {
        try simulatorController.devices()
            .toBlocking()
            .first()?
            .filter { $0.description.contains("iPhone 11") }
            .first
    }
    
    private func installAppBuilt(for target: Target) throws {
        logger.log(level: .notice, "Installing \(target.name)", metadata: .section)
        _ = try System.shared.observable(["/usr/bin/xcrun", "simctl", "install", "booted", "\(appPath!)"])
            .mapToString()
            .toBlocking()
            .last()
    }
    
    private func launchAppOnSimulator(for target: Target) throws {
        logger.log(level: .notice, "Launching \(target.name)", metadata: .section)
        _ = try System.shared.observable(["/usr/bin/xcrun", "simctl", "launch", "booted", "\(target.bundleId)"])
            .mapToString()
            .toBlocking()
            .last()
    }
}
