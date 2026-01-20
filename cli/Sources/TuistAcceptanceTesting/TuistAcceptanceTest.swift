import FileSystem
import Foundation
import Path
import Testing
import TuistSupport
import XcodeProj

public enum TuistAcceptanceTest {
    public static func expectFrameworkLinked(
        _ framework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        let frameworkDependencies = try target.frameworksBuildPhase()?.files?
            .compactMap(\.file)
            .map(\.nameOrPath)
            .filter { $0.hasSuffix(".framework") } ?? []
        guard frameworkDependencies.contains("\(framework).framework")
        else {
            Issue.record(
                "Target \(targetName) doesn't link the framework \(framework). It links the frameworks: \(frameworkDependencies.joined())",
                sourceLocation: sourceLocation
            )
            return
        }
    }

    public static func expectBundleCopiedFromCache(
        _ bundle: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)
        guard let buildFile = try target.resourcesBuildPhase()?.files?
            .first(where: { $0.file?.nameOrPath == "\(bundle).bundle" })
        else {
            Issue.record("Target \(targetName) doesn't copy the bundle \(bundle)", sourceLocation: sourceLocation)
            return
        }
        let bundlePath = try #require(try buildFile.file?.fullPath(sourceRoot: ""), sourceLocation: sourceLocation)
        if !bundlePath.contains(Environment.current.cacheDirectory.basename) {
            Issue.record(
                "The bundle '\(bundle)' copied from target '\(targetName)' has a path outside the cache: \(bundlePath)",
                sourceLocation: sourceLocation
            )
        }
    }

    public static func expectBundleCopiedFromBuildDirectory(
        _ bundle: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)
        guard let buildFile = try target.resourcesBuildPhase()?.files?
            .first(where: { $0.file?.nameOrPath == "\(bundle).bundle" })
        else {
            Issue.record("Target \(targetName) doesn't copy the bundle \(bundle)", sourceLocation: sourceLocation)
            return
        }
        let bundlePath = try buildFile.file?.fullPath(sourceRoot: "")
        if let bundlePath, bundlePath.contains(Environment.current.cacheDirectory.basename) {
            Issue.record(
                "The bundle '\(bundle)' copied from target '\(targetName)' has a path inside the cache: \(bundlePath)",
                sourceLocation: sourceLocation
            )
        }
    }

    public static func expectFrameworkEmbedded(
        _ framework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        let xcframeworkDependencies = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .map(\.files)
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.file?.nameOrPath)
            .filter { $0.contains(".framework") }
        guard xcframeworkDependencies.contains("\(framework).framework")
        else {
            Issue.record("Target \(targetName) doesn't embed the framework \(framework)", sourceLocation: sourceLocation)
            return
        }
    }

    public static func expectXCFrameworkEmbedded(
        _ xcframework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        let xcframeworkDependencies = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .map(\.files)
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.file?.nameOrPath)
            .filter { $0.contains(".xcframework") }
        guard xcframeworkDependencies.contains("\(xcframework).xcframework")
        else {
            Issue.record("Target \(targetName) doesn't link the xcframework \(xcframework)", sourceLocation: sourceLocation)
            return
        }
    }

    public static func expectXCFrameworkNotEmbedded(
        _ xcframework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        let xcframeworkDependencies = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .map(\.files)
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.file?.nameOrPath)
            .filter { $0.contains(".xcframework") }
        guard !xcframeworkDependencies.contains("\(xcframework).xcframework")
        else {
            Issue.record("Target \(targetName) links the xcframework \(xcframework)", sourceLocation: sourceLocation)
            return
        }
    }

    public static func expectXCFrameworkLinked(
        _ framework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        guard try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "\(framework).xcframework" }) == true
        else {
            Issue.record("Target \(targetName) doesn't link the xcframework \(framework)", sourceLocation: sourceLocation)
            return
        }
    }

    public static func expectXCFrameworkNotLinked(
        _ framework: String,
        by targetName: String,
        xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try requireTarget(targetName, in: xcodeproj, sourceLocation: sourceLocation)

        if try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "\(framework).xcframework" }) == true
        {
            Issue.record("Target \(targetName) links the xcframework \(framework)", sourceLocation: sourceLocation)
            return
        }
    }

    public static func requireTarget(
        _ targetName: String,
        in xcodeproj: XcodeProj,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> PBXTarget {
        let targets = xcodeproj.pbxproj.projects.flatMap(\.targets)
        return try #require(targets.first(where: { $0.name == targetName }), sourceLocation: sourceLocation)
    }
}
