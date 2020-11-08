import TSCBasic
import TuistSupport
import RxBlocking

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
            return "Carthage was not found either in Bundler nor in the environment"
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting: DependencyManagerInteracting {
}

// MARK: - Carthage Interactor

#warning("TODO: Add unit test!")
public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling!
    private let dependenciesDirectoryController: DependenciesDirectoryControlling!
    
    public init(
        fileHandler: FileHandling = FileHandler.shared,
        dependenciesDirectoryController: DependenciesDirectoryControlling = DependenciesDirectoryController()
    ) {
        self.fileHandler = fileHandler
        self.dependenciesDirectoryController = dependenciesDirectoryController
    }
    
    #warning("TODO: The hardes part here will be knowing whether we need to recompile the frameworks (Cartfile.resolved)")
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        #warning("TODO: How to determine platforms?")
        let platoforms: Set<CarthageCommandBuilder.Platform> = [.macOS, .watchOS]
        #warning("TODO: Replace stubbed values with reals.")
        let dependencies: [CartfileContentBuilder.Dependency] = [.github(name: "Alamofire/Alamofire", version: "5.0.4")]
        
        try withTemporaryDirectory { temporaryDirectoryPath in
            // create `carthage` shell command
            let commnad = try buildCarthageCommand(for: method, platforms: platoforms, path: temporaryDirectoryPath)
            
            // create `Cartfile`
            let cartfileContent = buildCarfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.touch(cartfilePath)
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)
            
            // load `Cartfile.resolved` from previous run
            try dependenciesDirectoryController.loadCartfileResolvedFile(from: path, temporaryDirectoryPath: temporaryDirectoryPath)
            
            // run `carthage`
            try System.shared.runAndPrint(commnad)
            
            // save `Cartfile.resolved`
            try dependenciesDirectoryController.saveCartfileResolvedFile(at: path, temporaryDirectoryPath: temporaryDirectoryPath)
            
            // save generated frameworks
            let names = dependencies.map { $0.name }
            #warning("TODO: dont pass names")
            try dependenciesDirectoryController.saveCarthageFrameworks(at: path, temporaryDirectoryPath: temporaryDirectoryPath, names: names)
        }
    }
    
    // MARK: - Helpers
    
    private func buildCarfileContent(for dependnecies: [CartfileContentBuilder.Dependency]) -> String {
        CartfileContentBuilder(dependencies: dependnecies)
            .build()
    }

    private func buildCarthageCommand(for method: InstallDependenciesMethod, platforms: Set<CarthageCommandBuilder.Platform>, path: AbsolutePath) throws -> [String] {
        let canUseBundler = canUseCarthageThroughBundler()
        let canUseSystem = canUseSystemCarthage()
        
        guard canUseBundler || canUseSystem else {
            throw CarthageInteractorError.carthageNotFound
        }
        
        return CarthageCommandBuilder(method: method, path: path)
            .platforms(platforms)
            .throughBundler(canUseBundler)
            .cacheBuilds(true)
            .newResolver(true)
            .build()
    }
    
    /// Returns true if CocoaPods is accessible through Bundler,
    /// and shoudl be used instead of the global CocoaPods.
    /// - Returns: True if Bundler can execute CocoaPods.
    private func canUseCarthageThroughBundler() -> Bool {
        do {
            try System.shared.run(["bundle", "info", "carthage"])
            return true
        } catch {
            return false
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
