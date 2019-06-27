import Foundation

// https://www.graphviz.org/doc/info/attrs.html#d:fixedsize
public enum DotGraphNodeAttribute: Equatable, Hashable, CustomStringConvertible {
    public enum Shape: String {
        case box
        case polygon
        case ellipse
        case oval
        case circle
    }

    /// The label of the node.
    case label(String)

    /// Nod eshape
    case shape(Shape)

    /// String representation of the attribute.
    public var description: String {
        switch self {
        case let .shape(shape):
            return "shape=\"\(shape)\""
        case let .label(label):
            return "label=\"\(label)\""
        }
    }
}
