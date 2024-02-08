//
//  GraphDefinition+ManifestMapper.swift
//  TuistLoader
//
//  Created by Stefano Mondino on 08/02/24.
//

import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.GraphDefinition {
    static func from(_ graph: ProjectDescription.GraphDefinition) -> TuistGraph.GraphDefinition {
        .init(fillColor: graph.fillColor.graphValue,
              textColor: graph.textColor?.graphValue,
              shape: .init(graph.shape.rawValue),
              strokeWidth: graph.strokeWidth)
    }
}
extension TuistGraph.GraphDefinition.Color {
    static func from(_ color: ProjectDescription.GraphDefinition.Color) -> TuistGraph.GraphDefinition.Color {
        .init(color)
    }
}

extension ProjectDescription.GraphDefinition.Color {
    var graphValue: TuistGraph.GraphDefinition.Color {
        .from(self)
    }
}
extension ProjectDescription.GraphDefinition {
    var graphValue: TuistGraph.GraphDefinition {
        .from(self)
    }
}
