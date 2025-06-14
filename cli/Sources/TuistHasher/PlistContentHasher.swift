import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol PlistContentHashing {
    func hash(plist: Plist) async throws -> String
}

/// `PlistContentHasher`
/// is responsible for computing a hash that uniquely identifies a property-list file (e.g. `Info.plist` or `.entitlements`)
public final class PlistContentHasher: PlistContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - PlistContentHashing

    public func hash(plist: Plist) async throws -> String {
        switch plist {
        case let .infoPlist(infoPlist):
            switch infoPlist {
            case let .variable(variable, configuration: _):
                return try contentHasher.hash(variable)
            case let .file(path: path, configuration: _):
                return try await contentHasher.hash(path: path)
            case let .dictionary(dictionary, configuration: _), let .extendingDefault(dictionary, configuration: _):
                var dictionaryString = ""
                for key in dictionary.keys.sorted() {
                    let value = dictionary[key, default: "nil"]
                    dictionaryString += "\(key)=\(value);"
                }
                return try contentHasher.hash(dictionaryString)
            case let .generatedFile(_, data, _):
                return try contentHasher.hash(data)
            }
        case let .entitlements(entitlements):
            switch entitlements {
            case let .variable(variable, configuration: _):
                return try contentHasher.hash(variable)
            case let .file(path, configuration: _):
                return try await contentHasher.hash(path: path)
            case let .dictionary(dictionary, configuration: _):
                var dictionaryString = ""
                for key in dictionary.keys.sorted() {
                    let value = dictionary[key, default: "nil"]
                    dictionaryString += "\(key)=\(value);"
                }
                return try contentHasher.hash(dictionaryString)
            case let .generatedFile(_, data, _):
                return try contentHasher.hash(data)
            }
        }
    }
}
