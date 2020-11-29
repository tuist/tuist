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
    /// - Parameter tuistDirectoryPath: The path to the directory that contains the `Tuist/` directory.
    /// - Parameter method: Installation method.
    /// - Parameter dependencies: List of dependencies to intall using `Carthage`.
    func install(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling
    private let carthageCommandGenerator: CarthageCommandGenerating
    private let cartfileContentGenerator: CartfileContentGenerating
    private let cartfileResolvedInteractor: CartfileResolvedInteracting
    private let carthageFrameworksInteractor: CarthageFrameworksInteracting

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator(),
        cartfileContentGenerator: CartfileContentGenerating = CartfileContentGenerator(),
        cartfileResolvedInteractor: CartfileResolvedInteracting = CartfileResolvedInteractor(),
        carthageFrameworksInteractor: CarthageFrameworksInteracting = CarthageFrameworksInteractor()
    ) {
        self.fileHandler = fileHandler
        self.carthageCommandGenerator = carthageCommandGenerator
        self.cartfileContentGenerator = cartfileContentGenerator
        self.cartfileResolvedInteractor = cartfileResolvedInteractor
        self.carthageFrameworksInteractor = carthageFrameworksInteractor
    }

    public func install(tuistDirectoryPath: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        // check availability of `carthage`
        guard canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }
        
        // determine platforms
        let platforms: Set<Platform> = dependencies
            .reduce(Set<Platform>()) { platforms, dependency in platforms.union(dependency.platforms) }

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // create `carthage` shell command
            let command = carthageCommandGenerator.command(method: method, path: temporaryDirectoryPath, platforms: platforms)

            // create `Cartfile`
            let cartfileContent = try cartfileContentGenerator.cartfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)

            // load `Cartfile.resolved` from previous run
            try cartfileResolvedInteractor.loadIfExist(from: tuistDirectoryPath, temporaryDirectoryPath: temporaryDirectoryPath)

            // run `carthage`
            try System.shared.runAndPrint(command)

            // save `Cartfile.resolved`
            try cartfileResolvedInteractor.save(at: tuistDirectoryPath, temporaryDirectoryPath: temporaryDirectoryPath)

            // save installed frameworks
            try carthageFrameworksInteractor.save(at: tuistDirectoryPath, temporaryDirectoryPath: temporaryDirectoryPath)
        }
    }

    // MARK: - Helpers

    private func copyFile(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.replace(toPath, with: fromPath)
        } else {
            try fileHandler.copy(from: fromPath, to: toPath)
        }
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
