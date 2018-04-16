import Foundation
import PathKit
import Unbox

extension Path {
    func assertRelative() throws {
        if !isRelative {
            throw "Path \(self) is not relative. Only relative paths are supported."
        }
    }

    func assertExists() throws {
        if !exists {
            throw "File/folder at path \(self) doesn't exist"
        }
    }
}

extension Path: UnboxableRawType {
    public static func transform(unboxedNumber _: NSNumber) -> Path? {
        return nil
    }

    public static func transform(unboxedString: String) -> Path? {
        return Path(unboxedString)
    }
}
