import Foundation
import TuistCore
import TuistSupport

enum CocoaPodsInteractorError: FatalError, Equatable {
    /// Thrown when CocoaPods cannot be found.
    case cocoapodsNotFound
    case outdatedRepository

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cocoapodsNotFound:
            return .abort
        case .outdatedRepository:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .cocoapodsNotFound:
            return "CocoaPods was not found either in Bundler nor in the environment"
        case .outdatedRepository:
            return "The installation of CocoaPods dependencies might have failed because the CocoaPods repository is outdated"
        }
    }
}

public protocol CocoaPodsInteracting {
    /// Runs 'pod install' for all the CocoaPods dependencies that have been indicated in the graph.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the pods fails.
    func install(graphTraverser: GraphTraversing) throws
}

public final class CocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    /// Runs 'pod install' for all the CocoaPods dependencies that have been indicated in the graph.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the pods fails.
    public func install(graphTraverser: GraphTraversing) throws {
        do {
            try install(graphTraverser: graphTraverser, updatingRepo: false)
        } catch let error as CocoaPodsInteractorError {
            if case CocoaPodsInteractorError.outdatedRepository = error {
                logger.warning("The local CocoaPods specs repository is outdated. Re-running 'pod install' updating the repository.")
                try self.install(graphTraverser: graphTraverser, updatingRepo: true)
            } else {
                throw error
            }
        }
    }

    fileprivate func install(graphTraverser: GraphTraversing, updatingRepo: Bool) throws {
        guard !graphTraverser.cocoapodsPaths().isEmpty else {
            return
        }

        let canUseBundler = canUseCocoaPodsThroughBundler()
        let canUseSystem = canUseSystemPod()

        try graphTraverser.cocoapodsPaths().sorted().forEach { path in
            var command: [String]

            if canUseBundler {
                command = ["bundle", "exec", "pod"]
            } else if canUseSystem {
                command = ["pod"]
            } else {
                throw CocoaPodsInteractorError.cocoapodsNotFound
            }

            command.append(contentsOf: ["install", "--project-directory=\(path.pathString)"])

            if updatingRepo {
                command.append("--repo-update")
            }

            // The installation of Pods might fail if the local repository that contains the specs
            // is outdated.
            logger.notice("Installing CocoaPods dependencies defined in \(path.pathString)", metadata: .section)

            var mightNeedRepoUpdate: Bool = false
            let outputClosure: ([UInt8]) -> Void = { bytes in
                let content = String(data: Data(bytes), encoding: .utf8)
                if content?.contains("CocoaPods could not find compatible versions for pod") == true {
                    mightNeedRepoUpdate = true
                }
            }
            do {
                try System.shared.runAndPrint(
                    command,
                    verbose: false,
                    environment: System.shared.env,
                    redirection: .stream(
                        stdout: outputClosure,
                        stderr: outputClosure
                    )
                )
            } catch {
                if mightNeedRepoUpdate {
                    throw CocoaPodsInteractorError.outdatedRepository
                } else {
                    throw error
                }
            }
        }
    }

    /// Returns true if CocoaPods is accessible through Bundler,
    /// and shoudl be used instead of the global CocoaPods.
    ///
    /// - Returns: True if Bundler can execute CocoaPods.
    fileprivate func canUseCocoaPodsThroughBundler() -> Bool {
        do {
            try System.shared.run(["bundle", "show", "cocoapods"])
            return true
        } catch {
            return false
        }
    }

    /// Returns true if CocoaPods is avaiable in the environment.
    ///
    /// - Returns: True if CocoaPods is available globally in the system.
    fileprivate func canUseSystemPod() -> Bool {
        do {
            _ = try System.shared.which("pod")
            return true
        } catch {
            return false
        }
    }
}
