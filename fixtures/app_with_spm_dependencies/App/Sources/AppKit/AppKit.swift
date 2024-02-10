//import Alamofire
//import ComposableArchitecture
import ZipArchive
import GoogleSignIn
import Yams
import Amplitude
import Sentry
import CleverTapSDK
import RealmSwift
// import CocoaLumberjackSwift

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        //        _ = AF.download("http://www.tuist.io")
        
        // Use ComposableArchitecture to make sure it links fine
        //        _ = EmptyReducer<Never, Never>()
        
        // Use ZipArchive
        _ = SSZipArchive.createZipFile(atPath: "", withFilesAtPaths: [])
        
        // Use Yams
        _ = YAMLEncoder()
        
        let _ = Amplitude()
        
        SentrySDK.startSession()
        
//        let _ = DDFileLogger()
    }
}
//
//@Reducer
//struct Counter {
//    struct State: Equatable {
//        var count = 0
//    }
//
//    enum Action {
//        case decrementButtonTapped
//        case incrementButtonTapped
//    }
//
//    var body: some Reducer<State, Action> {
//        Reduce { state, action in
//            switch action {
//            case .decrementButtonTapped:
//                state.count -= 1
//                return .none
//            case .incrementButtonTapped:
//                state.count += 1
//                return .none
//            }
//        }
//    }
//}
