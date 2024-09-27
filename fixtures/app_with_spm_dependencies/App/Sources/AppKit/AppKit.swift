import Alamofire
import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
import CocoaLumberjackSwift
import CrashReporter
import GoogleMobileAds
import GoogleSignIn
import libzstd
import MarkdownUI
import NYTPhotoViewer
import Realm
import RealmSwift
import Sentry
import SVProgressHUD
import Yams
import ZipArchive

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use ZipArchive
        _ = SSZipArchive.createZipFile(atPath: #file + "/ss.zip", withFilesAtPaths: [])

        // Use Yams
        _ = YAMLEncoder()

        // Use GoogleSignIn
        _ = GIDSignIn.sharedInstance.hasPreviousSignIn()

        // Use Sentry
        SentrySDK.startSession()

        // Use CocoaLumberjack
        _ = DDOSLogger.sharedInstance

        // Use Realm
        _ = Realm.Configuration()

        // Use AppCenter
        AppCenter.start(withAppSecret: "{Your App Secret}", services: [Analytics.self, Crashes.self])

        // Use libzstd
        _ = ZDICT_isError(0)

        // Use NYTPhotoViewer
        _ = NYTPhotosOverlayView()

        // Use SVProgressHUD
        SVProgressHUD.show()

        // Use MarkdownUI
        _ = BulletedList(of: [""])
    }
}
