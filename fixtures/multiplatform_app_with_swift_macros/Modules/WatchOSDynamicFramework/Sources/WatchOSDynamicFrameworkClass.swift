import ComposableArchitecture
import Foundation
import MultiPlatformTransitiveDynamicFramework
import StructBuilder

@Buildable
struct Watch {
    let name: String
}

// @Reducer is a Swift Macro that generates other macros

@Reducer
struct Counter {
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            case .incrementButtonTapped:
                state.count += 1
                return .none
            }
        }
    }
}

public class WatchOSDynamicFrameworkClass {
    //    let watch = WatchBuilder(name: "ultra-2")

    public init() {}
    public func print() {
        MultiPlatformTransitiveDynamicFrameworkClass().print()
        Swift.print("WatchOSDynamicFramework")
    }
}
