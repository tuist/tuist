import Alamofire
import ComposableArchitecture
import ZipArchive
import GoogleSignIn
import Yams
import Sentry
import RealmSwift
import CocoaLumberjackSwift
import Realm

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
        _ = GIDSignIn.sharedInstance.configuration
        
        // Use Sentry
        SentrySDK.startSession()
        
        // Use CocoaLumberjack
        let _ = CocoaLumberjackSwift.DDLogInfo("Log")
        
        // Use Realm
        let _ = Realm.Configuration()
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
