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
    /// - name: Swift Package / Project name
    /// - settings:  Project Settings
    /// - targets:  Project Targets
    /// - configuration: Configure automatic schemes and resource accessors generation
    /// for Swift Packages i.e ["package_name":  ProjectConfiguration]
    static func from(
        name: String,
        settings: ProjectDescription.Settings?,
        targets: [ProjectDescription.Target],
        projectConfiguration: TuistGraph.Project.ProjectConfiguration?
    ) -> Self {
        /// Default options
        /// Avoid polluting workspace with unnecessary schemes
        var options: ProjectDescription.Project.Options = .options(automaticSchemesOptions: .disabled)

        if let configuration = projectConfiguration,
           let mappedConfiguration = try? ProjectDescription.Project.ProjectConfiguration.from(manifest: configuration)
        {
            options = mappedConfiguration.options
        }

        return ProjectDescription.Project(
            name: name,
            options: options,
            settings: settings,
            targets: targets,
            resourceSynthesizers: .default
        )
    }
}
