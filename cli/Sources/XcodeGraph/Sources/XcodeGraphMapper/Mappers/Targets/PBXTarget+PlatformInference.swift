import Foundation
import Path
import XcodeGraph
import XcodeProj

enum PlatformInferenceError: LocalizedError, Equatable {
    case noPlatformInferred(String)

    var errorDescription: String? {
        switch self {
        case let .noPlatformInferred(name):
            return "No platform could be inferred from target '\(name)'."
        }
    }
}

extension PBXTarget {
    /// Determines the set of `Destinations` supported by this target.
    ///
    /// Attempts to identify platforms from:
    /// 1. `SDKROOT` (if present)
    /// 2. Deployment targets
    /// 3. Product type as a final fallback
    ///
    /// Supports multi-platform scenarios by unioning destinations from all inferred platforms.
    ///
    /// - Returns: A `Destinations` set representing all supported destinations.
    /// - Throws: If retrieving deployment targets fails.
    func platform() throws -> Destinations {
        if let sdkNames = buildConfigurationList?.stringSettings(for: .sdkroot),
           let sdkName = sdkNames.values.first,
           let root = Platform(sdkroot: sdkName)
        {
            return root.destinations
        } else {
            return try inferPlatformFromTarget()
        }
    }

    /// Infers the platform from deployment targets if `SDKROOT` is not set or recognized.
    ///
    /// Aggregates all platforms indicated by the deployment targets. If none are found,
    /// picks a default based on product type:
    /// - iOS for most apps, clips, and app extensions.
    /// - macOS for frameworks, libraries, command line tools, macros, xpc, system extensions.
    /// - tvOS for tvTopShelfExtension.
    /// - iOS otherwise.
    ///
    /// - Returns: A `Destinations` set representing all inferred destinations.
    /// - Throws: If retrieving deployment targets fails.
    private func inferPlatformFromTarget() throws -> Destinations {
        let deploymentTargets = deploymentTargets()
        var result = Destinations()

        if deploymentTargets.iOS != nil {
            result.formUnion(Platform.iOS.destinations)
        }
        if deploymentTargets.macOS != nil {
            result.formUnion(Platform.macOS.destinations)
        }
        if deploymentTargets.watchOS != nil {
            result.formUnion(Platform.watchOS.destinations)
        }
        if deploymentTargets.tvOS != nil {
            result.formUnion(Platform.tvOS.destinations)
        }
        if deploymentTargets.visionOS != nil {
            result.formUnion(Platform.visionOS.destinations)
        }

        guard result.isEmpty else { return result }

        let productType = productType?.mapProductType()
        let product = try productType.throwing(PlatformInferenceError.noPlatformInferred(name))

        switch product {
        case .app, .stickerPackExtension, .appClip, .appExtension:
            return Platform.iOS.destinations
        case .framework, .staticLibrary, .dynamicLibrary, .commandLineTool, .macro, .xpc,
             .systemExtension:
            return Platform.macOS.destinations
        case .tvTopShelfExtension:
            return Platform.tvOS.destinations
        case .watch2App, .watch2Extension:
            return Platform.watchOS.destinations
        default:
            return Platform.iOS.destinations
        }
    }
}
