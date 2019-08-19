import Foundation
import TuistCore

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

protocol CocoaPodsInteracting {
    /// Runs 'pod install' for all the CocoaPods dependencies that have been indicated in the graph.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the pods fails.
    func install(graph: Graphing) throws
}

final class CocoaPodsInteractor: CocoaPodsInteracting {
    /// Instance to run commands in the system.
    let system: Systeming

    /// Initializes the CocoaPods
    ///
    /// - Parameters:
    ///   - system: Instance to run commands in the system.
    init(system: Systeming = System()) {
        self.system = system
    }

    /// Runs 'pod install' for all the CocoaPods dependencies that have been indicated in the graph.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the pods fails.
    func install(graph: Graphing) throws {
        do {
            try install(graph: graph, updatingRepo: false)
        } catch let error as CocoaPodsInteractorError {
            if case CocoaPodsInteractorError.outdatedRepository = error {
                Context.shared.printer.print(warning: "The local CocoaPods specs repository is outdated. Re-running 'pod install' updating the repository.")
                try self.install(graph: graph, updatingRepo: true)
            } else {
                throw error
            }
        }
    }

    fileprivate func install(graph: Graphing, updatingRepo: Bool) throws {
        guard !graph.cocoapods.isEmpty else {
            return
        }

        let canUseBundler = canUseCocoaPodsThroughBundler()
        let canUseSystem = canUseSystemPod()

        try graph.cocoapods.forEach { node in
            var command: [String]

            if canUseBundler {
                command = ["bundle", "exec", "pod"]
            } else if canUseSystem {
                command = ["pod"]
            } else {
                throw CocoaPodsInteractorError.cocoapodsNotFound
            }

            command.append(contentsOf: ["install", "--project-directory=\(node.path.pathString)"])

            if updatingRepo {
                command.append("--repo-update")
            }

            // The installation of Pods might fail if the local repository that contains the specs
            // is outdated.
            Context.shared.printer.print(section: "Installing CocoaPods dependencies defined in \(node.podfilePath)")
            var mightNeedRepoUpdate: Bool = false
            let outputClosure: ([UInt8]) -> Void = { bytes in
                let content = String(data: Data(bytes), encoding: .utf8)
                if content?.contains("CocoaPods could not find compatible versions for pod") == true {
                    mightNeedRepoUpdate = true
                }
            }
            do {
                try system.runAndPrint(command,
                                       verbose: false,
                                       environment: system.env,
                                       redirection: .stream(stdout: outputClosure,
                                                            stderr: outputClosure))
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
            try system.run(["bundle", "show", "cocoapods"])
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
            _ = try system.which("pod")
            return true
        } catch {
            return false
        }
    }
}
