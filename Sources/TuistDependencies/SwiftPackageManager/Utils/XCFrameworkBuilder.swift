import TSCBasic
import TuistGraph
import TuistSupport
import TuistCore
import RxSwift
import RxBlocking

public protocol XCFrameworkBuilding {
    func buildXCFrameworks(
        using packageInfo: PackageInfo,
        platforms: Set<Platform>,
        outputDirectory: AbsolutePath
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
        using packageInfo: PackageInfo,
        platforms: Set<Platform>,
        outputDirectory: AbsolutePath
    ) throws -> [AbsolutePath] {
        let projectPath = outputDirectory.appending(component: packageInfo.xcodeProjectName)
        let scheme = packageInfo.scheme
        
        let frameworksPathsGroupedByName = try platforms
            .intersection(packageInfo.supportedPlatforms)
            .reduce(into: [String: [AbsolutePath]](), { result, platform in
                logger.info("Building \(packageInfo.name) for \(platform.caseValue)...")
                
                let frameworks = try platform.sdks
                    .flatMap { try buildFramework(projectPath: projectPath, scheme: scheme, sdk: $0, outputDirectory: outputDirectory) }
                result.merge(frameworks, uniquingKeysWith: { $0 + $1 })
            })
        
        let xcFrameworksPaths = try frameworksPathsGroupedByName
            .reduce(into: [AbsolutePath]()) { result, next in
                let name = next.key
                let frameworks = next.value
                
                logger.info("Creating XCFramework for \(name)...")
                
                let xcframeworks = try buildXCFramework(name: name, frameworks: frameworks, outputDirectory: outputDirectory)
                result.append(xcframeworks)
            }
        
        return xcFrameworksPaths
    }
    
    // MARK: - Helpers
    
    private func buildFramework(
        projectPath: AbsolutePath,
        scheme: String,
        sdk: Platform.SDK,
        outputDirectory: AbsolutePath
    ) throws -> [String: [AbsolutePath]] {
        let archivePath = outputDirectory.appending(component: sdk.archiveName)
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
        name: String,
        frameworks: [AbsolutePath],
        outputDirectory: AbsolutePath
    ) throws -> AbsolutePath {
        let output = outputDirectory.appending(component: name + ".xcframework")
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
