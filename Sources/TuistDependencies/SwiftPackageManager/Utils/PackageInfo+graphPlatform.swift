import Foundation
import ProjectDescription
import TuistGraph
import TuistSupport

extension PackageInfo.Platform {
    func graphPlatform() throws -> TuistGraph.Platform {
        switch platformName.lowercased() {
        case "ios", "maccatalyst":
            return .iOS
        case "macos":
            return .macOS
        case "tvos":
            return .tvOS
        case "watchos":
            return .watchOS
        case "visionos":
            return .visionOS
        default:
            throw PackageInfoMapperError.unknownPlatform(platformName)
        }
    }

    func destinations() throws -> ProjectDescription.Destinations {
        switch platformName.lowercased() {
        case "ios":
            return [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
        case "maccatalyst":
            return [.macCatalyst]
        case "macos":
            return [.mac]
        case "tvos":
            return [.appleTv]
        case "watchos":
            return [.appleWatch]
        case "visionos":
            return [.appleVision]
        default:
            throw PackageInfoMapperError.unknownPlatform(platformName)
        }
    }
}
