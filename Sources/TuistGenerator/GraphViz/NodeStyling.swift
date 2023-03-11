import Foundation
import GraphViz
import TuistCore
import TuistGraph

extension GraphViz.Node {
    mutating func applyAttributes(attributes: NodeStyleAttributes?) {
        // For some unknown reason, the compiler requires using explicit self here
        // swiftformat:disable redundantSelf
        self.fillColor = attributes?.fillColor
        self.textColor = attributes?.textColor
        self.strokeWidth = attributes?.strokeWidth
        self.shape = attributes?.shape
        // swiftformat:enable redundantSelf
    }
}

struct NodeStyleAttributes {
    let fillColor: GraphViz.Color?
    var textColor: GraphViz.Color?
    let strokeWidth: Double?
    let shape: GraphViz.Node.Shape?

    init(
        fillColorName: GraphViz.Color.Name? = nil,
        textColorName: GraphViz.Color.Name? = nil,
        strokeWidth: Double? = nil,
        shape: GraphViz.Node.Shape? = nil
    ) {
        fillColor = fillColorName.map { GraphViz.Color.named($0) }
        textColor = textColorName.map { GraphViz.Color.named($0) }
        self.strokeWidth = strokeWidth
        self.shape = shape
    }
}

extension GraphTarget {
    var styleAttributes: NodeStyleAttributes {
        switch target.product {
        case .app, .watch2App, .commandLineTool, .appClip, .xpc:
            return .init(fillColorName: .deepskyblue, strokeWidth: 1.5, shape: .box3d)
        case .appExtension, .watch2Extension, .tvTopShelfExtension:
            return .init(fillColorName: .deepskyblue2, shape: .component)
        case .messagesExtension, .stickerPackExtension:
            return .init(fillColorName: .springgreen2, shape: .component)
        case .framework:
            return .init(fillColorName: .darkgoldenrod1, shape: .cylinder)
        case .staticLibrary:
            return .init(fillColorName: .coral1)
        case .staticFramework:
            return .init(fillColorName: .coral1, shape: .cylinder)
        case .dynamicLibrary:
            return .init(fillColorName: .darkgoldenrod3)
        case .bundle:
            return .init(fillColorName: .grey90, shape: .rectangle)
        case .uiTests, .unitTests:
            return .init(fillColorName: .limegreen, shape: .octagon)
        }
    }
}

extension GraphDependency {
    func styleAttributes(
        graphTraverser: GraphTraversing
    ) -> NodeStyleAttributes? {
        switch self {
        case .sdk:
            return .init(fillColorName: .violet, shape: .rectangle)
        case .framework:
            return .init(fillColorName: .darkgoldenrod3, shape: .trapezium)
        case .library:
            return .init(fillColorName: .lightgray, shape: .folder)
        case .bundle:
            return .init(fillColorName: .aliceblue, shape: .box)
        case .packageProduct:
            return .init(fillColorName: .tan4, textColorName: .white, shape: .tab)
        case .xcframework:
            return .init(fillColorName: .lightskyblue1, shape: .trapezium)
        case let .target(name: name, path: path):
            return graphTraverser.target(path: path, name: name)
                .map(\.styleAttributes)
        }
    }
}
