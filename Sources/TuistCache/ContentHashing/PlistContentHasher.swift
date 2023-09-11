import Foundation
import TuistCore
import TuistGraph

public protocol PlistContentHashing {
    func hash(plist: Plist) throws -> String
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

    public func hash(plist: Plist) throws -> String {
        switch plist {
        case .infoPlist(let infoPlist):
            switch infoPlist {
            case let .file(path):
                return try contentHasher.hash(path: path)
            case let .dictionary(dictionary), let .extendingDefault(dictionary):
                var dictionaryString: String = ""
                for key in dictionary.keys.sorted() {
                    let value = dictionary[key, default: "nil"]
                    dictionaryString += "\(key)=\(value);"
                }
                return try contentHasher.hash(dictionaryString)
            case let .generatedFile(_, data):
                return try contentHasher.hash(data)
            }
        case .entitlements(let entitlements):
            switch entitlements {
            case let .file(path):
                return try contentHasher.hash(path: path)
            case let .dictionary(dictionary):
                var dictionaryString: String = ""
                for key in dictionary.keys.sorted() {
                    let value = dictionary[key, default: "nil"]
                    dictionaryString += "\(key)=\(value);"
                }
                return try contentHasher.hash(dictionaryString)
            case let .generatedFile(_, data):
                return try contentHasher.hash(data)
            }
        }
    }
}
