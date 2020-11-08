import Foundation
import TSCBasic
import TuistSupport
import RxBlocking

// MARK: - Carthage Interacting

public protocol CarthageInteracting: DependencyManagerInteracting {
}

// MARK: - Carthage Interactor

#warning("TODO: Add unit test!")
public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling!
    
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    #warning("TODO: check if carthage installed, throw error if not")
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        #warning("TODO: How to determine platforms?")
        let platoforms: Set<CarthageCommandBuilder.Platform> = [.macOS]
        #warning("TODO: Replace stubbed values with reals.")
        let dependencies: [CartfileContentBuilder.Dependency] = [.github(name: "Alamofire/Alamofire", version: "5.0.4")]
        
        #warning("TODO: Check if Cartfile.resolved already exist under `Tuist/*`")
        try withTemporaryDirectory { temporaryDirectoryPath in
            // create `carthage` shell command
            let commnad = buildCarthageCommand(for: method, platforms: platoforms, path: temporaryDirectoryPath)
            
            // create `Cartfile`
            let cartfileContent = buildCarfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.touch(cartfilePath)
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)
            
            // run `carthage`
            try System.shared.runAndPrint(commnad)
            
            // copy `Cartfile.resolved`
            let cartfileResolvedDestinationPath = path.appending(components: "Tuist", "Dependencies", "Lockfiles", "Cartfile.resolved")
            let cartfileResolvedPath = temporaryDirectoryPath.appending(component: "Cartfile.resolved")
            try fileHandler.delete(cartfileResolvedDestinationPath)
            try fileHandler.copy(from: cartfileResolvedPath, to: cartfileResolvedDestinationPath)
            
            print(try fileHandler.contentsOfDirectory(temporaryDirectoryPath.appending(components: "Carthage", "Build", "Mac", "Alamofire.framework")))
            
            // copy frameworks
            let decoder = JSONDecoder()
            var aleardyCopied = Set<String>()
            try dependencies
                .map { $0.name }
                .forEach { dependencyName in
                    let versionFilePath = temporaryDirectoryPath.appending(components: "Carthage", "Build", ".\(dependencyName).version")
                    let versionFileData = try fileHandler.readFile(versionFilePath)
                    let version = try decoder.decode(CarthageVersion.self, from: versionFileData)
                    
                    #warning("TODO: add rest platforms support")
                    try version.macOS.forEach {
                        guard aleardyCopied.contains($0.name) else { return }
                        
                        let frameworkPath = temporaryDirectoryPath.appending(components: "Carthage", "Build", "Mac", "\($0.name).framework")
                        let frameworkDestinationPath = path.appending(components: "Tuist", "Dependencies", $0.name, "macOS", "\($0.name).framework")
                        try fileHandler.delete(frameworkDestinationPath)
                        try fileHandler.copy(from: frameworkPath, to: frameworkDestinationPath)
                        
                        aleardyCopied.insert($0.name)
                    }
                }
            
            // update `graph.json`
            #warning("TODO: update graph.json")
        }
    }
    
    private func buildCarfileContent(for dependnecies: [CartfileContentBuilder.Dependency]) -> String {
        CartfileContentBuilder(dependencies: dependnecies)
            .build()
    }
    
    #warning("TODO: run via bundler or not?")
    private func buildCarthageCommand(for method: InstallDependenciesMethod, platforms: Set<CarthageCommandBuilder.Platform>, path: AbsolutePath) -> [String] {
        CarthageCommandBuilder(method: method, path: path)
            .platforms(platforms)
            .cacheBuilds(true)
            .newResolver(true)
            .build()
    }
}


struct CarthageVersion: Decodable {
    enum CodingKeys: String, CodingKey {
        case commitish
        case iOS
        case macOS = "Mac"
        case tvOS
        case watchOS
    }
    
    let commitish: String
    let iOS: [Dependency]
    let macOS: [Dependency]
    let tvOS: [Dependency]
    let watchOS: [Dependency]
    
    struct Dependency: Decodable {
        let hash: String
        let name: String
        let linking: String
        let swiftToolchainVersion: String
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commitish = try container.decode(String.self, forKey: .commitish)
        iOS = try container.decodeIfPresent([Dependency].self, forKey: .iOS) ?? []
        macOS = try container.decodeIfPresent([Dependency].self, forKey: .macOS) ?? []
        tvOS = try container.decodeIfPresent([Dependency].self, forKey: .tvOS) ?? []
        watchOS = try container.decodeIfPresent([Dependency].self, forKey: .watchOS) ?? []
    }
}

struct DependenciesGraph: Codable {
    struct Dependency: Codable {
        let name: String
        let depenencies: [String]
    }
    
    let dependencies: [Dependency]
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
