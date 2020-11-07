import TSCBasic
import TuistSupport
import RxBlocking

// MARK: - Carthage Interacting

public protocol CarthageInteracting: DependencyManagerInteracting {
}

// MARK: - Carthage Interactor

#warning("Add unit test!")
public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling!
    
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    #warning("TODO: check if carthage installed, throw error if not")
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        #warning("Check if Cartfile.resolved already exist under `Tuist/*`")
        try withTemporaryDirectory { temporaryDirectoryPath in
            let commnad = buildCarthageCommand(for: method, path: temporaryDirectoryPath)
            let cartfileContent = buildCarfileContent()
            
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.touch(cartfilePath)
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)
            
            
            print("At:")
            print(temporaryDirectoryPath)
            print("Cartfile:")
            print(cartfileContent)
            
            let arguments = commnad.components(separatedBy: " ")
            try System.shared.runAndPrint(arguments)
            
            print(try fileHandler.contentsOfDirectory(temporaryDirectoryPath))
            
            let cartfileResolvedPath = temporaryDirectoryPath.appending(component: "Cartfile.resolved")
            
            if !fileHandler.exists(cartfileResolvedPath) {
                #warning("TODO: throw - no Cartfile.resolved")
            }
            
//            let iOSBuildsPath = temporaryDirectoryPath.appending(components: "Build", "iOS")
//            if !fileHandler.exists(iOSBuildsPath) {
//                #warning("TODO: throw - no iOS builds")
//            }
            
            
            let cartfileResolvedDestinationPath = path.appending(components: "Tuist", "Dependencies", "Lockfiles")
            try fileHandler.copy(from: cartfileResolvedPath, to: path)
        }
    }
    
    #warning("TODO: Replace stubbed values with reals.")
    private func buildCarfileContent() -> String {
        CartfileContentBuilder(
            dependencies: [
                .github(name: "Alamofire/Alamofire", version: "5.4.0"),
            ]
        ).build()
    }
    
    #warning("TODO: Replace stubbed values with reals.")
    #warning("TODO: how to determine platforms?")
    #warning("TODO: run via bundler or not?")
    private func buildCarthageCommand(for method: InstallDependenciesMethod, path: AbsolutePath) -> String {
        CarthageCommandBuilder(method: method, path: path)
            .platforms([.macOS])
            .cacheBuilds(true)
            .newResolver(true)
            .build()
    }
}


//// MARK: - Helpers
//
///// Returns true if CocoaPods is accessible through Bundler,
///// and shoudl be used instead of the global CocoaPods.
///// - Returns: True if Bundler can execute CocoaPods.
//private func canUseCarthageThroughBundler() -> Bool {
//    do {
//        try System.shared.run(["bundle", "info", "carthage"])
//        return true
//    } catch {
//        return false
//    }
//}
//
///// Returns true if Carthage is avaiable in the environment.
///// - Returns: True if Carthege is available globally in the system.
//private func canUseSystemCarthage() -> Bool {
//    do {
//        _ = try System.shared.which("carthage")
//        return true
//    } catch {
//        return false
//    }
//}
