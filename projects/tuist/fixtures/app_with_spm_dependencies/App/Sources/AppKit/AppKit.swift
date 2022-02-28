import Alamofire
import Charts
import ComposableArchitecture
import FBSDKCoreKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseDatabase
import FirebaseFirestore

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use Charts to make sure it links fine
        _ = BarChartView()

        // Use Facebook to make sure it links fine
        Settings.setAdvertiserTrackingEnabled(true)

        // Use FirebaseAnalytics to make sure it links fine
        Analytics.logEvent("Event", parameters: [:])

        // Use FirebaseDatabase to make sure it links fine
        Database.database(app: FirebaseApp.app()!).reference().setValue("value")

        // Use FirebaseFirestore to make sure it links fine
        _ = Firestore.firestore()
    }
}
