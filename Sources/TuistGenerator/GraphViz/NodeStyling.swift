import Foundation
import GraphViz
import TuistCore

extension GraphViz.Node {
    mutating func applyAttributes(attributes: NodeStyleAttributes?) {
        self.fillColor = attributes?.fillColor
        self.strokeWidth = attributes?.strokeWidth
        self.shape = attributes?.shape
    }
}

struct NodeStyleAttributes {
    let fillColor: GraphViz.Color?
    let strokeWidth: Double?
    let shape: GraphViz.Node.Shape?

    init(colorName: GraphViz.Color.Name? = nil,
         strokeWidth: Double? = nil,
         shape: GraphViz.Node.Shape? = nil) {
        self.fillColor = colorName.map { GraphViz.Color.named($0) }
        self.strokeWidth = strokeWidth
        self.shape = shape
    }
}

extension GraphNode {
    var styleAttributes: NodeStyleAttributes? {
        if self is SDKNode {
            return .init(colorName: .blueviolet, shape: .rectangle)
        }

        if self is CocoaPodsNode {
            return .init(colorName: .red2)
        }

        if self is FrameworkNode {
            return .init(colorName: .darkgoldenrod3, shape: .trapezium)
        }

        if self is LibraryNode {
            return .init(colorName: .lightgray, shape: .folder)
        }

        if self is PackageProductNode {
            return .init(colorName: .tan4, shape: .tab)
        }

        if self is PrecompiledNode {
            return .init(colorName: .skyblue, shape: .trapezium)
        }

        if let targetNode = self as? TargetNode {
            switch targetNode.target.product {
            case .app, .watch2App:
                return .init(colorName: .deepskyblue, strokeWidth: 1.5, shape: .box3d)
            case .appExtension, .watch2Extension:
                return .init(colorName: .deepskyblue2, shape: .component)
            case .framework:
                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .staticLibrary:
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .staticFramework:
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .dynamicLibrary
//                return .init(colorName: .darkgoldenrod1, shape: .cylinder)
//            case .bundle: return .named()
//            case .uiTests, .unitTests:
            default: return nil
            }
        }

        return nil
    }
}

