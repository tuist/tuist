//
//  Destination+ManifestMapper.swift
//  
//
//  Created by Michael Simons on 7/3/23.
//

import Foundation
import TuistGraph
import ProjectDescription

extension TuistGraph.Destination {
    /// Maps a ProjectDescription.Package instance into a TuistGraph.Package model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    ///   - generatorPaths: Generator paths.
    static func from(platform: ProjectDescription.Platform, deploymentTarget: ProjectDescription.DeploymentTarget?) throws -> TuistGraph.Destinations {
        switch (platform, deploymentTarget) {
        case (.macOS, _):
            return [.mac]
        case (.iOS, .some(.iOS(_, let devices, supportsMacDesignedForIOS: let supportsMacDesignedForIOS))):
            var destinations: [Destination] = []
            
            if devices.contains(.iphone) {
                destinations.append(.iPhone)
            }
            
            if devices.contains(.ipad) {
                destinations.append(.iPad)
            }
           
            if devices.contains(.mac) {
                destinations.append(.macCatalyst)
            }
            
            if supportsMacDesignedForIOS {
                destinations.append(.macWithiPadDesign)
            }
            
            return Set(destinations)
        case (.iOS, _):
            return .iOS
        case (.tvOS, _):
            return .tvOS
        case (.watchOS, _):
            return .watchOS
        }
    }
}
