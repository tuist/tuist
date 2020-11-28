import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Carthage Interactor Errors

enum CarthageInteractorError: FatalError, Equatable {
    /// Thrown when CocoaPods cannot be found.
    case carthageNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found either in Bundler nor in the environment."
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting {
    /// Installes `Carthage` dependencies.
    /// - Parameter path: Directory whose project's dependencies will be installed.
    /// - Parameter method: Installation method.
    /// - Parameter dependencies: List of dependencies to intall using `Carthage`.
    func install(
        at path: AbsolutePath,
        method: InstallDependenciesMethod,
        dependencies: [CarthageDependency]
    ) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling
    private let carthageCommandGenerator: CarthageCommandGenerating
    private let cartfileResolvedInteractor: CartfileResolvedInteracting
    private let carthageFrameworksInteractor: CarthageFrameworksInteracting

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator(),
        cartfileResolvedInteractor: CartfileResolvedInteracting = CartfileResolvedInteractor(),
        carthageFrameworksInteractor: CarthageFrameworksInteracting = CarthageFrameworksInteractor()
    ) {
        self.fileHandler = fileHandler
        self.carthageCommandGenerator = carthageCommandGenerator
        self.cartfileResolvedInteractor = cartfileResolvedInteractor
        self.carthageFrameworksInteractor = carthageFrameworksInteractor
    }

    #warning("TODO: The hardes part here will be knowing whether we need to recompile the frameworks")
    public func install(
        at path: AbsolutePath,
        method: InstallDependenciesMethod,
        dependencies: [CarthageDependency]
    ) throws {
        // check availability of `carthage`
        guard canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }
        
        // determine platforms
        let platoforms: Set<Platform> = dependencies
            .reduce(Set<Platform>()) { platforms, dependency in platforms.union(dependency.platforms) }

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // create `carthage` shell command
            let command = carthageCommandGenerator.command(method: method, path: temporaryDirectoryPath, platforms: platoforms)

            // create `Cartfile`
            let cartfileContent = try buildCarfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.touch(cartfilePath)
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)

            // load `Cartfile.resolved` from previous run
            try cartfileResolvedInteractor.loadIfExist(from: path, temporaryDirectoryPath: temporaryDirectoryPath)

            // run `carthage`
            try System.shared.runAndPrint(command)

            // save `Cartfile.resolved`
            try cartfileResolvedInteractor.save(at: path, temporaryDirectoryPath: temporaryDirectoryPath)

            // save installed frameworks
            try carthageFrameworksInteractor.save(at: path, temporaryDirectoryPath: temporaryDirectoryPath)
        }
    }

    // MARK: - Helpers

    private func buildCarfileContent(for dependencies: [CarthageDependency]) throws -> String {
        try CartfileContentBuilder(dependencies: dependencies)
            .build()
    }

    /// Returns true if Carthage is avaiable in the environment.
    /// - Returns: True if Carthege is available globally in the system.
    private func canUseSystemCarthage() -> Bool {
        do {
            _ = try System.shared.which("carthage")
            return true
        } catch {
            return false
        }
    }
}
