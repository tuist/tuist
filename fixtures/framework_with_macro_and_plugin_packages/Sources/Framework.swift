import Buildable
import ComposableArchitecture
import Foundation

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

@Reducer
struct Feature {
    struct State {}

    enum Action {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
