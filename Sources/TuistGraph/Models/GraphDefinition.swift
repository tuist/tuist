//
//  GraphDefinition.swift
//  TuistGraph
//
//  Created by Stefano Mondino on 08/02/24.
//

import Foundation

public struct GraphDefinition: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Codable {

    public struct Color: Codable, ExpressibleByStringInterpolation, CustomStringConvertible, Equatable, Hashable {
        public let description: String
        public init(stringLiteral: String) {
            self.description = stringLiteral
        }
        public init(_ value: CustomStringConvertible) {
            self.description = value.description
        }
    }
    
    public struct Shape: Codable, ExpressibleByStringInterpolation, CustomStringConvertible, Equatable, Hashable {
        public let description: String
        public init(stringLiteral: String) {
            self.description = stringLiteral
        }
        public init(_ value: CustomStringConvertible) {
            self.description = value.description
        }
    }
    
    public var description: String { [fillColor as CustomStringConvertible?,
                                      textColor,
                                      shape,
                                      strokeWidth]
        .compactMap { $0?.description }.joined(separator: " - ") }
    
    public var debugDescription: String { description }
    
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
    
    public init(fillColor: GraphDefinition.Color,
                textColor: GraphDefinition.Color? = nil,
                shape: GraphDefinition.Shape,
                strokeWidth: Double? = nil) {
        self.fillColor = fillColor
        self.textColor = textColor
        self.shape = shape
        self.strokeWidth = strokeWidth
    }
    
}
