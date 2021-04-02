import TSCBasic
import TuistGraph
import TuistSupport
import TuistCore
import RxSwift
import RxBlocking

public protocol XCFrameworkBuilding {
    /// Builds an XCFrameworks for package's products.
    /// - Parameters:
    ///   - path: A working directory.
    ///   - packageInfo: A description of a package.
    ///   - platforms: List of platforms that architectures will be included into produced XCFramework.
    /// - Returns: List of paths of produced XCFrameworks.
    func buildXCFrameworks(
        at path: AbsolutePath,
        packageInfo: PackageInfo,
        platforms: Set<Platform>
    ) throws -> [AbsolutePath]
}

public final class XCFrameworkBuilder: XCFrameworkBuilding {
    private let fileHandler: FileHandling
    private let xcodeBuildController: XcodeBuildControlling
    
    public init(
        fileHandler: FileHandling = FileHandler.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(formatter: Formatter())
    ) {
        self.fileHandler = fileHandler
        self.xcodeBuildController = xcodeBuildController
    }
    
    public func buildXCFrameworks(
        at path: AbsolutePath,
        packageInfo: PackageInfo,
        platforms: Set<Platform>
    ) throws -> [AbsolutePath] {
        let projectPath = path.appending(component: packageInfo.xcodeProjectName)
        let scheme = packageInfo.scheme
        
        let frameworksPathsGroupedByName = try platforms
            .intersection(packageInfo.supportedPlatforms)
            .reduce(into: [String: [AbsolutePath]](), { result, platform in
                logger.info("Building \(packageInfo.name) for \(platform.caseValue)...")
                
                let frameworks = try platform.sdks
                    .flatMap { try buildFramework(at: path, projectPath: projectPath, scheme: scheme, sdk: $0) }
                result.merge(frameworks, uniquingKeysWith: { $0 + $1 })
            })
        
        let xcFrameworksPaths = try frameworksPathsGroupedByName
            .reduce(into: [AbsolutePath]()) { result, next in
                let name = next.key
                let frameworks = next.value
                
                logger.info("Creating XCFramework for \(name)...")
                
                let xcframeworks = try buildXCFramework(at: path, name: name, frameworks: frameworks)
                result.append(xcframeworks)
            }
        
        return xcFrameworksPaths
    }
    
    // MARK: - Helpers
    
    private func buildFramework(
        at path: AbsolutePath,
        projectPath: AbsolutePath,
        scheme: String,
        sdk: Platform.SDK
    ) throws -> [String: [AbsolutePath]] {
        let archivePath = path.appending(component: sdk.archiveName)
        _ = try xcodeBuildController
            .archive(
                .project(projectPath),
                scheme: scheme,
                clean: false,
                archivePath: archivePath,
                arguments: [
                    .destination(sdk.destination),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
            .ignoreElements()
            .toBlocking()
            .last()
        
        let frameworksDirectory = archivePath.appending(components: "Products", "Library", "Frameworks")
        let frameworksPaths = try fileHandler
            .contentsOfDirectory(frameworksDirectory)
            .filter { $0.extension == "framework" }
        
        return Dictionary(grouping: frameworksPaths, by: \.basenameWithoutExt)
    }
    
    private func buildXCFramework(
        at path: AbsolutePath,
        name: String,
        frameworks: [AbsolutePath]
    ) throws -> AbsolutePath {
        let output = path.appending(component: name + ".xcframework")
        _ = try xcodeBuildController
            .createXCFramework(frameworks: frameworks, output: output)
            .ignoreElements()
            .toBlocking()
            .last()
        
        return output
    }
}

// MARK: - Helpers

private extension Platform {
    struct SDK {
        let archiveName: String
        let destination: String
    }
    
    var sdks: [SDK] {
        switch self {
        case .iOS:
            return [
                SDK(
                    archiveName: "iphoneos.xcarchive",
                    destination: "generic/platform=iOS"
                ),
                SDK(
                    archiveName: "iphonesimulator.xcarchive",
                    destination: "generic/platform=iOS Simulator"
                )
            ]
        case .tvOS:
            return [
                SDK(
                    archiveName: "appletvos.xcarchive",
                    destination: "generic/platform=tvOS"
                ),
                SDK(
                    archiveName: "appletvsimulator.xcarchive",
                    destination: "generic/platform=tvOS Simulator"
                )
            ]
        case .watchOS:
            return [
                SDK(
                    archiveName: "watchos.xcarchive",
                    destination: "generic/platform=watchOS"
                ),
                SDK(
                    archiveName: "watchsimulator.xcarchive",
                    destination: "generic/platform=watchOS Simulator"
                )
            ]
        case .macOS:
            return [
                SDK(
                    archiveName: "macosx.xcarchive",
                    destination: "generic/platform=macOS"
                )
            ]
        }
    }
}
