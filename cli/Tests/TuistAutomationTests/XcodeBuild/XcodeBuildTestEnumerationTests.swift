import Testing
@testable import TuistAutomation

struct XcodeBuildTestEnumerationTests {
    @Test func dropsTheActionTheBundleAndTheFiltersThatWouldHideCandidates() {
        let arguments = [
            "clean", "test",
            "-workspace", "App.xcworkspace",
            "-scheme", "App",
            "-destination", "platform=iOS Simulator,name=iPhone 16",
            "-resultBundlePath", "/tmp/run.xcresult",
            "-only-testing", "AppTests/MathTests",
            "-only-testing:CoreTests",
            "-skip-testing:AppTests/SlowTests",
            "-test-iterations", "3",
            "-retry-tests-on-failure",
            "-enableCodeCoverage", "YES",
            "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]

        #expect(XcodeBuildController.enumerationArguments(from: arguments) == [
            "-workspace", "App.xcworkspace",
            "-scheme", "App",
            "-destination", "platform=iOS Simulator,name=iPhone 16",
            "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=NO",
        ])
    }

    @Test func keepsAnXctestrunAndTheTestProducts() {
        #expect(
            XcodeBuildController.enumerationArguments(
                from: ["test-without-building", "-xctestrun", "App.xctestrun", "-testProductsPath", "App.xctestproducts"]
            ) == ["-xctestrun", "App.xctestrun", "-testProductsPath", "App.xctestproducts"]
        )
    }
}
