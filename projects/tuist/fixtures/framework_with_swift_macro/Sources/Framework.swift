import Foundation

import StructBuilder

@Buildable
public struct Person {
    let name: String
    let age: Int
    let hobby: String?

    var likesReading: Bool {
        hobby == "Reading"
    }

    static let minimumAge = 21
}
