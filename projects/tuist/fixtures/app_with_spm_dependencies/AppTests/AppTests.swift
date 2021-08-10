import Foundation
import Quick
import Nimble
import XCTest

@testable import App

// Use Quick&Nimble to make sure they link fine
class CrashTests: QuickSpec {
  override func spec() {
      context("when importing Nimble through SPM") {
        it("tests can be built properly") {
            expect(AppDelegate().hello()).to(equal("AppDelegate.hello()"))
        }
      }
  }
}
