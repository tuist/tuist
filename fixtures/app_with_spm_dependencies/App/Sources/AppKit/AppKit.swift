import Alamofire
import CocoaLumberjackSwift
import ComposableArchitecture
import GoogleSignIn
import Realm
import RealmSwift
import Sentry
import Yams
import ZipArchive

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use ComposableArchitecture to make sure it links fine
        _ = EmptyReducer<Never, Never>()

        // Use ZipArchive
        _ = SSZipArchive.createZipFile(atPath: #file + "/ss.zip", withFilesAtPaths: [])

        // Use Yams
        _ = YAMLEncoder()

        // Use GoogleSignIn
        _ = GIDSignIn.sharedInstance.hasPreviousSignIn()

        // Use Sentry
        SentrySDK.startSession()

        // Use CocoaLumberjack
        _ = CocoaLumberjackSwift.DDLogInfo("Log")

        // Use Realm
        _ = Realm.Configuration()
    }
}

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
