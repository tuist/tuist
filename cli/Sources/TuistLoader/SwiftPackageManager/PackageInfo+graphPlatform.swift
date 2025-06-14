import Foundation
import ProjectDescription
import TuistSupport
import XcodeGraph

extension PackageInfo.Platform {
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
