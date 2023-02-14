import Alamofire
import ComposableArchitecture
import FBSDKCoreKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseDatabase
import FirebaseFirestore
import GRDB
import IterableSDK
import Stripe
import Styles
import TYStatusBarView

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use Facebook to make sure it links fine
        Settings.shared.isAdvertiserTrackingEnabled = true

        // Use FirebaseAnalytics to make sure it links fine
        Analytics.logEvent("Event", parameters: [:])

        // Use FirebaseDatabase to make sure it links fine
        if let firebaseApp = FirebaseApp.app() {
            Database.database(app: firebaseApp).reference().setValue("value")
            // Use FirebaseCrashlytics to make sure it links fine
            _ = Crashlytics.crashlytics()

            // Use FirebaseFirestore to make sure it links fine
            _ = Firestore.firestore()
        }

        // Use Stripe to make sure it links fine
        _ = STPAPIClient.shared

        // Use IterableSDK to make sure it links fine
        _ = IterableSDK.IterableAPI.sdkVersion

        // Use GRDB to make sure it links fine
        try? DatabasePool(path: NSTemporaryDirectory().appending("db.sqlite")).erase()

        // Use Styles from LocalSwiftPackage
        print(Styles.Color.orange)
    }
}
