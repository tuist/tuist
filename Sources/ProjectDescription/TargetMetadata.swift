//
//  TargetMetadata.swift
//  Tuist
//
//  Created by msimons on 10/17/24.
//

import Foundation

public protocol AdditionalMetadataRepresentable {
    var metadata: MetadataValue { get }
}

public struct TargetMetadata: Codable, Equatable, Sendable {
    
    // let tags: [String]
    public let additionalMetadata: MetadataValue
    
    public init(additionalMetadata: AdditionalMetadataRepresentable) {
        self.additionalMetadata = additionalMetadata.metadata
    }

}

// This enables us to round trip arbitrary JSON without needing to know a specific type.
public enum MetadataValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case number(Double)
    case dictionary([String: MetadataValue])
    case array([MetadataValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        let parsers = [
            { MetadataValue.bool(try container.decode(Bool.self)) },
            { MetadataValue.int(try container.decode(Int.self)) },
            { MetadataValue.number(try container.decode(Double.self)) },
            { MetadataValue.string(try container.decode(String.self)) },
            { MetadataValue.array(try container.decode([MetadataValue].self)) },
            { MetadataValue.dictionary(try container.decode([String: MetadataValue].self)) },
        ]
        
        for parser in parsers {
            do {
                self = try parser()
                return
            } catch DecodingError.typeMismatch {
                continue
            }
        }
        
        self = .null
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let bool): try container.encode(bool)
        case .int(let int): try container.encode(int)
        case .number(let double): try container.encode(double)
        case .string(let string): try container.encode(string)
        case .array(let list): try container.encode(list)
        case .dictionary(let dictionary): try container.encode(dictionary)
        case .null: try container.encodeNil()
        }
    }
}
