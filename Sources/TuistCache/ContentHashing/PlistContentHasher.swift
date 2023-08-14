import Foundation
import TuistCore
import TuistGraph

public protocol PlistContentHashing {
    func hash<T: PListTypesProtocol>(plist: T) throws -> String
}

/// `PListContentHasher`
/// is responsible for computing a hash that uniquely identifies a property-list file (e.g. `Info.plist` or `.entitlements`)
public final class PListContentHasher: PlistContentHashing {
    private let contentHasher: ContentHashing
    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - PListContentHashing

    public func hash<T: PListTypesProtocol>(plist: T) throws -> String {
        // TODO: DRY, improve generalization
        if let plist = plist as? InfoPlist {
            switch plist {
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
        } else if let plist = plist as? Entitlements {
            switch plist {
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
        } else {
            throw ""
        }
    }
}


