import Foundation
import RxBlocking
import TSCBasic
import TuistAutomation
import TuistCore
import TuistSupport
import struct TSCUtility.Version

enum TestServiceError: FatalError {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutTestableTargets(scheme: String)
    
    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutTestableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        }
    }
    
    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound:
            return .abort
        case .schemeWithoutTestableTargets:
            return .abort
        }
    }
}

final class TestService {
    /// Project generator
    let projectGenerator: ProjectGenerating
    
    /// Xcode build controller.
    let xcodebuildController: XcodeBuildControlling
    
    /// Build graph inspector.
    let buildGraphInspector: BuildGraphInspecting
    
    /// Simulator controller
    let simulatorController: SimulatorControlling
    
    init(
        projectGenerator: ProjectGenerating = ProjectGenerator(),
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController()
    ) {
        self.projectGenerator = projectGenerator
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
    }
    
    func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath,
        iphone: String?,
        ios: String?
    ) throws {
        let graph: Graph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try projectGenerator.generateWithGraph(path: path, projectOnly: false).1
        } else {
            graph = try projectGenerator.load(path: path)
        }
        
        let platform: Platform?
        let version: Version?
        if let ios = ios {
            platform = .iOS
            version = ios.version()
        } else {
            platform = nil
            version = nil
        }
        
        let deviceName: String?
        if let iphone = iphone {
            deviceName = "iPhone \(iphone)"
        } else {
            deviceName = nil
        }
        
        let testableSchemes = buildGraphInspector.testableSchemes(graph: graph)
        logger.log(level: .notice, "Found the following testable schemes: \(testableSchemes.map(\.name).joined(separator: ", "))")
        
        if let schemeName = schemeName {
            guard let scheme = testableSchemes.first(where: { $0.name == schemeName }) else {
                throw TestServiceError.schemeNotFound(scheme: schemeName, existing: testableSchemes.map(\.name))
            }
            try testScheme(
                scheme: scheme,
                graph: graph,
                path: path,
                clean: clean,
                configuration: configuration,
                platform: platform,
                version: version,
                deviceName: deviceName
            )
        } else {
            var cleaned: Bool = false
            try testableSchemes.forEach {
                try testScheme(
                    scheme: $0,
                    graph: graph,
                    path: path,
                    clean: !cleaned && clean,
                    configuration: configuration,
                    platform: platform,
                    version: version,
                    deviceName: deviceName
                )
                cleaned = true
            }
        }
        
        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)
    }
    
    // MARK: - private
    
    private func testScheme(
        scheme: Scheme,
        graph: Graph,
        path: AbsolutePath,
        clean: Bool,
        configuration: String?,
        platform: Platform?,
        version: Version?,
        deviceName: String?
    ) throws {
        logger.log(level: .notice, "Testing scheme \(scheme.name)", metadata: .section)
        guard let buildableTarget = buildGraphInspector.testableTarget(scheme: scheme, graph: graph) else {
            throw TestServiceError.schemeWithoutTestableTargets(scheme: scheme.name)
        }
        
        let device = try simulatorController.findAvailableDevice(
            platform: platform,
            version: version,
            deviceName: deviceName
        )
            .toBlocking()
            .last()
        
        let workspacePath = try buildGraphInspector.workspacePath(directory: path)!
        _ = try xcodebuildController.test(
            .workspace(workspacePath),
            scheme: scheme.name,
            clean: clean,
            destination: .device(device!!.udid),
            arguments: buildGraphInspector.buildArguments(target: buildableTarget, configuration: configuration)
        )
            .printFormattedOutput()
            .toBlocking()
            .last()
    }
}
