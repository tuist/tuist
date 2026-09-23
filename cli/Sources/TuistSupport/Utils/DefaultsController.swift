import Command
import Foundation
import Mockable

@Mockable
public protocol DefaultsControlling {
    func setPackageDendencySCMToRegistryTransformation(
        _ packageDendencySCMToRegistryTransformation: PackageDendencySCMToRegistryTransformation
    ) async throws
}

public enum PackageDendencySCMToRegistryTransformation {
    case useRegistryIdentityAndSources
}

public struct DefaultsController: DefaultsControlling {
    private let commandRunner: CommandRunning

    public init(
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.commandRunner = commandRunner
    }

    public func setPackageDendencySCMToRegistryTransformation(
        _ packageDendencySCMToRegistryTransformation: PackageDendencySCMToRegistryTransformation
    ) async throws {
        let value = switch packageDendencySCMToRegistryTransformation {
        case .useRegistryIdentityAndSources:
            "useRegistryIdentityAndSources"
        }
        try await commandRunner.run(
            arguments: [
                "/usr/bin/defaults",
                "write",
                "com.apple.dt.Xcode",
                "IDEPackageDependencySCMToRegistryTransformation",
                value,
            ]
        )
        .awaitCompletion()
    }
}
