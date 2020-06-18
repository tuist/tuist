import Foundation
import TuistCore

public protocol InfoPlistContentHashing {
    func hash(plist: InfoPlist) throws -> String
}

/// `InfoPlistContentHasher`
/// is responsible for computing a hash that uniquely identifies a `InfoPlist`
public final class InfoPlistContentHasher: InfoPlistContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - InfoPlistContentHashing

    public func hash(plist: InfoPlist) throws -> String {
        switch plist {
        case let .file(path):
            return try contentHasher.hash(fileAtPath: path)
        case let .dictionary(dictionary), let .extendingDefault(dictionary):
            var dictionaryString: String = ""
            for key in dictionary.keys.sorted() {
                let value = dictionary[key, default: "nil"]
                dictionaryString += "\(key)=\(value);"
            }
            return try contentHasher.hash(dictionaryString)
        }
    }
}
