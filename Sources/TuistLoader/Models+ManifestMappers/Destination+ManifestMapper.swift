import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.Destination {
    /// Maps a ProjectDescription.Package instance into a XcodeGraph.Package model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    ///   - generatorPaths: Generator paths.
    static func from(
        destinations: ProjectDescription.Destinations
    ) throws -> XcodeGraph.Destinations {
        let mappedDestinations: [XcodeGraph.Destination] = destinations.map { destination in
            switch destination {
            case .iPhone:
                return .iPhone
            case .iPad:
                return .iPad
            case .mac:
                return .mac
            case .macWithiPadDesign:
                return .macWithiPadDesign
            case .macCatalyst:
                return .macCatalyst
            case .appleWatch:
                return .appleWatch
            case .appleTv:
                return .appleTv
            case .appleVision:
                return .appleVision
            case .appleVisionWithiPadDesign:
                return .appleVisionWithiPadDesign
            }
        }

        return Set(mappedDestinations)
    }
}
