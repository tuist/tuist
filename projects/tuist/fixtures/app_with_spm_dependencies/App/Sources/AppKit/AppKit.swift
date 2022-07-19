import Alamofire
import Charts
import ComposableArchitecture
import FBSDKCoreKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseRemoteConfig
import IterableSDK
import Stripe
import TYStatusBarView

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use Charts to make sure it links fine
        _ = BarChartView()

        // Use Facebook to make sure it links fine
        Settings.shared.isAdvertiserTrackingEnabled = true

        // Use FirebaseAnalytics to make sure it links fine
        Analytics.logEvent("Event", parameters: [:])

        // Use FirebaseDatabase to make sure it links fine
        Database.database(app: FirebaseApp.app()!).reference().setValue("value")

        // Use FirebaseCrashlytics to make sure it links fine
        _ = Crashlytics.crashlytics()

        // Use FirebaseFirestore to make sure it links fine
        _ = Firestore.firestore()
        
        // Use Functions to make sure it links fine
        _ = Functions.functions()
        
        // Use RemoteConfig to make sure it links fine
        _ = RemoteConfig.remoteConfig()

        // Use Stripe to make sure it links fine
        _ = STPAPIClient.shared

        // Use IterableSDK to make sure it links fine
        _ = IterableSDK.IterableAPI.sdkVersion
    }
}
