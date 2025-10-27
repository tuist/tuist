
import Nimble
import Quick

class TableOfContentsSpec: QuickSpec {
    override class func spec() {
        describe("the 'Documentation' directory") {
            it("has everything you need to get started") {
                expect("foo").to(contain("foo"))
            }
        }
    }
}
