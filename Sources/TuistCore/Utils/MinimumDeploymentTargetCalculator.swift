import Foundation
import TuistGraph
import TuistSupport

/// When generating the graph for Swift Packages, we need to infer a minimum deployment target
/// for the packages that don't define it. The SPM does it by obtaining it from the system's XCTest
/// framework so we are mimicking that logic here:
/// https://github.com/apple/swift-package-manager/blob/fb989898f76e0c694a4547ba7ffc8b0e40199545/Sources/Workspace/DefaultPluginScriptRunner.swift#L158
public protocol MinimumDeploymentTargetCalculating {
    /// Returns the minimum deployment target for all the available platforms.
    /// - Returns: A dictionary with the platform as the key, and the minimum deployment target of the platform as a value.
    func allPlatforms() throws -> [Platform: DeploymentTarget]
}

/// The default implementation of MinimumDeploymentTargetCalculating
public class MinimumDeploymentTargetCalculator: MinimumDeploymentTargetCalculating {
    private let lock = NSLock()
    private var _allPlatforms: [Platform: DeploymentTarget]!

    public init() {}

    public func allPlatforms() throws -> [Platform: DeploymentTarget] {
        lock.lock()
        defer { lock.unlock() }
        if let _allPlatforms = _allPlatforms { return _allPlatforms }
        _allPlatforms = try fetchAllPlatforms()
        return _allPlatforms
    }

    fileprivate func fetchAllPlatforms() throws -> [Platform: DeploymentTarget] {
        return try Platform.allCases.reduce(into: [Platform: DeploymentTarget]()) { acc, next in
            let sdk = TuistGraph.Platform(rawValue: next.rawValue)!.xcodeSdkRoot
            let sdkPlatformPath = try System.shared.capture("/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-platform-path").spm_chomp()
            let xcTestRelativePath = "Developer/Library/Frameworks/XCTest.framework/XCTest"
            let sdkInfo = try System.shared.capture("/usr/bin/xcrun", "vtool", "-show-build", "\(sdkPlatformPath)/\(xcTestRelativePath)")

            var lines = sdkInfo.components(separatedBy: "\n")
            while !lines.isEmpty {
                let first = lines.removeFirst()
                if first.contains("platform \(next.vtoolPlatform)"),
                    let line = lines.first, line.contains("minos")
                {
                    let versionString = line.components(separatedBy: " ").last!
                    let deploymentTarget: DeploymentTarget
                    switch next {
                    case .iOS:
                        deploymentTarget = .iOS(versionString, [.ipad, .iphone])
                    case .macOS:
                        deploymentTarget = .macOS(versionString)
                    case .tvOS:
                        deploymentTarget = .tvOS(versionString)
                    case .watchOS:
                        deploymentTarget = .watchOS(versionString)
                    }

                    acc[next] = deploymentTarget
                }
            }
        }
    }
}

private extension Platform {
    var vtoolPlatform: String {
        switch self {
        case .macOS:
            return "MACOS"
        case .iOS:
            return "IOS"
        case .tvOS:
            return "TVOS"
        case .watchOS:
            return "WATCHOS"
        }
    }
}

// OUR LOGIC

// let minDeploymentTargets: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget]
// minDeploymentTargets = try Set(targetToPlatforms.values).reduce(into: [:]) { result, platform in
//    // Calculate the minimum deployment target for a given platform, by analyzing the corresponding XCTest framework using `vtool`
//    let sdk = TuistGraph.Platform(rawValue: platform.rawValue)!.xcodeSdkRoot
//    let sdkPlatformPath = try System.shared.capture("/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-platform-path").spm_chomp()
//    let xcTestRelativePath = "Developer/Library/Frameworks/XCTest.framework/XCTest"
//    let sdkInfo = try System.shared.capture("/usr/bin/xcrun", "vtool", "-show-build", "\(sdkPlatformPath)/\(xcTestRelativePath)")
//    guard let fromMinVersion = sdkInfo.components(separatedBy: " version ").dropFirst().first.map({ String($0) }),
//        let minVersion = fromMinVersion.split(separator: "\n").first.map({ String($0) })
//    else {
//        throw PackageInfoMapperError.minDeploymentTargetParsingFailed(platform)
//    }
//
//    switch platform {
//    case .iOS:
//        result[platform] = .iOS(targetVersion: minVersion, devices: [.iphone, .ipad])
//    case .macOS:
//        result[platform] = .macOS(targetVersion: minVersion)
//    case .watchOS:
//        result[platform] = .watchOS(targetVersion: minVersion)
//    case .tvOS:
//        result[platform] = .tvOS(targetVersion: minVersion)
//    }
// }

// guard let (_, platformName) = platform.sdkNameAndPlatform else {
//    return nil
// }
//
// let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "vtool", "-show-build", binaryPath.pathString])
// var lines = try runResult.utf8Output().components(separatedBy: "\n")
// while !lines.isEmpty {
//    let first = lines.removeFirst()
//    if first.contains("platform \(platformName)"), let line = lines.first, line.contains("minos") {
//        return line.components(separatedBy: " ").last.map(PlatformVersion.init(stringLiteral:))
//    }
// }

//
// xcrun vtool -show-build /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest
/// Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture x86_64):
// Load command 8
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACOS
//    minos 11.0
//      sdk 12.0
//   ntools 1
//     tool LD
//  version 711.0
// Load command 9
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACCATALYST
//    minos 13.1
//      sdk 15.0
//   ntools 1
//     tool LD
//  version 711.0
/// Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture arm64):
// Load command 8
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACOS
//    minos 11.0
//      sdk 12.0
//   ntools 1
//     tool LD
//  version 711.0
// Load command 9
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACCATALYST
//    minos 14.0
//      sdk 15.0
//   ntools 1
//     tool LD
//  version 711.0
/// Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture arm64e):
// Load command 9
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACOS
//    minos 11.0
//      sdk 12.0
//   ntools 1
//     tool LD
//  version 711.0
// Load command 10
//      cmd LC_BUILD_VERSION
//  cmdsize 32
// platform MACCATALYST
//    minos 14.0
//      sdk 15.0
//   ntools 1
//     tool LD
//  version 711.0
