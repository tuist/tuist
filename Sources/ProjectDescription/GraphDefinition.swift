//
//  GraphDefinition.swift
//  TuistGraph
//
//  Created by Stefano Mondino on 08/02/24.
//

import Foundation

public struct GraphDefinition: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Codable {
    
    public enum Shape: String, Hashable, Codable {
        case box, rectangle, square, circle, ellipse, point, egg, triangle, plaintext, plain, diamond, trapezium, parallelogram, house, hexagon, octagon, doublecircle, doubleoctagon, invtriangle, invtrapezium, invhouse, Mdiamond, Msquare, Mcircle, polygon, oval, star, cylinder, note, tab, folder, box3d, component, cds, signature
    }
    
    public struct Color: Codable, ExpressibleByStringInterpolation, CustomStringConvertible, Equatable, Hashable {
        public let description: String
        public init(stringLiteral: String) {
            self.description = stringLiteral
        }
        public init(_ value: String) {
            self.description = value
        }
    }
    
    public var description: String { "" }
    
    public var debugDescription: String { "" }
    
    public var fillColor: Color
    public var textColor: Color?
    public var shape: Shape
    public var strokeWidth: Double?
    internal init(fillColor: GraphDefinition.Color,
                  textColor: GraphDefinition.Color? = nil,
                  strokeWidth: Double? = nil,
                  shape: GraphDefinition.Shape) {
        self.fillColor = fillColor
        self.textColor = textColor
        self.shape = shape
    }
    
    
}
