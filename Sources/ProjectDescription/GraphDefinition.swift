import Foundation

/// A styling definition to be used when elements are rendered in graphs
public struct GraphDefinition: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Codable {
    /// The shape of the object
    public enum Shape: String, Hashable, Codable {
        case box, rectangle, square, circle, ellipse, point, egg, triangle, plaintext, plain, diamond, trapezium, parallelogram,
             house, hexagon, octagon, doublecircle, doubleoctagon, invtriangle, invtrapezium, invhouse, Mdiamond, Msquare,
             Mcircle,
             polygon, oval, star, cylinder, note, tab, folder, box3d, component, cds, signature
    }

    /// The color of the object. Can either be an hex string like "#FFCC00" or a color name like "black", "teal", etc.
    public struct Color: Codable, ExpressibleByStringInterpolation, CustomStringConvertible, Equatable, Hashable {
        public let description: String
        public init(stringLiteral: String) {
            description = stringLiteral
        }

        public init(_ value: String) {
            description = value
        }
    }

    public var description: String { [
        fillColor as CustomStringConvertible?,
        textColor,
        shape.rawValue,
        strokeWidth,
    ]
    .compactMap { $0?.description }.joined(separator: " - ")
    }

    public var debugDescription: String { description }

    public var fillColor: Color
    public var textColor: Color?
    public var shape: Shape
    public var strokeWidth: Double?
    init(
        fillColor: GraphDefinition.Color,
        textColor: GraphDefinition.Color? = nil,
        strokeWidth _: Double? = nil,
        shape: GraphDefinition.Shape
    ) {
        self.fillColor = fillColor
        self.textColor = textColor
        self.shape = shape
    }

    /// Returns a graph definition
    /// - Parameters:
    ///   - fillColor: The color used to fill the shape
    ///   - textColor: The color used to write text over the shape. When nil, the graph rendering engine will use its internal
    /// default value. Defaults to nil.
    ///   - strokeWidth: The width of the stroke for borders. Defaults to nil.
    ///   - shape: The shape used to draw the node in the graph.
    public static func graph(
        fillColor: GraphDefinition.Color,
        textColor: GraphDefinition.Color? = nil,
        strokeWidth: Double? = nil,
        shape: GraphDefinition.Shape
    ) -> GraphDefinition {
        .init(
            fillColor: fillColor,
            textColor: textColor,
            strokeWidth: strokeWidth,
            shape: shape
        )
    }
}
