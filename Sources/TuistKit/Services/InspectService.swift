import Foundation
import RxBlocking
import Signals
import TSCBasic
import TuistCache
import TuistCore
import TuistDoc
import TuistSupport

// MARK: - InspectServiceError

enum InspectServiceError: FatalError, Equatable {
    case targetNotFound(name: String)

    var description: String {
        switch self {
        case let .targetNotFound(name):
            return "The target '\(name)' was not found."
        }
    }

    var type: ErrorType {
        switch self {
        case .targetNotFound:
            return .abort
        }
    }
}

// MARK: - InspectServicing

protocol InspectServicing {
    func run(path: AbsolutePath, target targetName: String) throws
}

// MARK: - InspectService

final class InspectService: InspectServicing {
    
    private let generator: Generating

    init(generator: Generating = Generator(contentHasher: CacheContentHasher()))
    {
        self.generator = generator
    }

    func run(path: AbsolutePath, target targetName: String) throws {
        let graph = try generator.load(path: path)
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)
        
//        let targets = graphTraverser.tar
//        let targets = graph.targets
//            .flatMap(\.value)
//            .filter { !$0.dependsOnXCTest }

        guard let target = targets.first(where: { $0.name == targetName }) else {
            throw InspectServiceError.targetNotFound(name: targetName)
        }
        
        let allDependencies = graph.findAll(targetNode: target, test: { _ in return true }, skip: { _ in return false })
        let dynamicDependencies = allDependencies.filter({ dependency -> Bool in
            if let library = dependency as? LibraryNode { return library.linking == .dynamic }
            if let framework = dependency as? FrameworkNode { return framework.linking == .dynamic }
            if let xcframework = dependency as? XCFrameworkNode { return xcframework.linking == .dynamic }
            if let target = dependency as? TargetNode { return !target.target.product.isStatic }
            return false
        })
        
        logger.info("Here are some information about the target '\(targetName)':", metadata: .section)
        
        logger.info("Target:", metadata: .subsection)
        logger.info(" - Product: \(target.target.product.rawValue)")
        logger.info(" - Bundle identifier: \(target.target.bundleId)")
        logger.info(" - Static: \(target.target.product.isStatic)")
        logger.info(" - Sources: \(target.target.sources.count)")
        logger.info(" - Resources: \(target.target.resources.count)")

        logger.info("Dependencies:", metadata: .subsection)
        logger.info(" - Dependencies: \(allDependencies.count)")
        logger.info(" - Direct dependencies: \(target.dependencies.count)")
        logger.info(" - Transitive dependencies: \(allDependencies.count - target.dependencies.count)")
        logger.info(" - Dynamic dependencies: \(dynamicDependencies.count)")
    }
}
