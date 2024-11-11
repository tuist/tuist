import ComposableArchitecture

@Reducer
public struct FeatureBReducer {
    @ObservableState
    public struct State: Equatable {
        var count = 0
        public init() {}
    }

    public enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
    }
    
    public init() {}

    public var body: some Reducer<State, Action> {
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
