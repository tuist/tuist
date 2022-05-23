//
//  Project+ManifestMapper.swift
//  TuistDependencies
//
//  Created by Shahzad Majeed on 5/23/22.
//

import ProjectDescription
import TuistGraph

extension ProjectDescription.Project {
    /// Maps a TuistGraph.Project instance into a ProjectDescription.Project instance.
    /// - Parameters:
    /// - manifest: Manifest representation of tuist project
    static func from(
        name: String,
        settings: ProjectDescription.Settings?,
        targets: [ProjectDescription.Target],
        options: TuistGraph.Project.Options,
        resourceSynthesizers _: [TuistGraph.ResourceSynthesizer]
    ) -> Self {
        /// TODO: Ignore `resourceSynthesizers` param for now as it requires us to expose some dependencies
        /// from `TuistLoader`. Also, mapping from `.file` to `.plugin` isn't straightforward. This work can be
        /// done incrementally in another PR
        ProjectDescription.Project(
            name: name,
            options: .from(manifest: options),
            settings: settings,
            targets: targets,
            resourceSynthesizers: .default
        )
    }
}
