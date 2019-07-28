import Foundation
import TuistCore

enum CocoaPodsInteractorError: FatalError, Equatable {
    /// Thrown when CocoaPods cannot be found.
    case cocoapodsNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cocoapodsNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .cocoapodsNotFound:
            return "CocoaPods was not found either in Bundler nor in the environment"
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
    /// Instance to output information to the user.
    let printer: Printing

    /// Instance to run commands in the system.
    let system: Systeming

    /// Initializes the CocoaPods
    ///
    /// - Parameters:
    ///   - printer: Instance to output information to the user.
    ///   - system: Instance to run commands in the system.
    init(printer: Printing = Printer(),
         system: Systeming = System()) {
        self.printer = printer
        self.system = system
    }

    /// Runs 'pod install' for all the CocoaPods dependencies that have been indicated in the graph.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the pods fails.
    func install(graph: Graphing) throws {
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

            command.append(contentsOf: ["install", "--project-directory=\(node.path.pathString)", "--repo-update"])

            printer.print(section: "Installing CocoaPods dependencies defined in \(node.podfilePath)")

            try system.runAndPrint(command)
        }
    }

    /// Returns true if CocoaPods is accessible through Bundler,
    /// and shoudl be used instead of the global CocoaPods.
    ///
    /// - Returns: True if Bundler can execute CocoaPods.
    func canUseCocoaPodsThroughBundler() -> Bool {
        do {
            try system.runAndPrint(["bundle", "show", "cocoapods"])
            return true
        } catch {
            return false
        }
    }

    /// Returns true if CocoaPods is avaiable in the environment.
    ///
    /// - Returns: True if CocoaPods is available globally in the system.
    func canUseSystemPod() -> Bool {
        do {
            _ = try system.which("pod")
            return true
        } catch {
            return false
        }
    }
}
