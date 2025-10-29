import Foundation
import RealmSwift

public class Framework3File {
    public init() {}

    public func hello() -> String {
        let obj = RealmObject()
        print(obj)
        return "Framework3File.hello()"
    }
}

final class RealmObject: GeoPoint {}
