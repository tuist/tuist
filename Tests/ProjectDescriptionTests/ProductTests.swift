import Foundation
@testable import ProjectDescription
import XCTest

final class ProductTests: XCTestCase {
    func test_toJSON() {
        assertCodableEqualToJson([Product.app], "[\"app\"]")
        assertCodableEqualToJson([Product.staticLibrary],"[\"staticLibrary\"]")
        assertCodableEqualToJson([Product.dynamicLibrary],"[\"dynamicLibrary\"]")
        assertCodableEqualToJson([Product.framework],"[\"framework\"]")
        assertCodableEqualToJson([Product.unitTests],"[\"unitTests\"]")
        assertCodableEqualToJson([Product.uiTests],"[\"uiTests\"]")
        assertCodableEqualToJson([Product.appExtension],"[\"appExtension\"]")
        assertCodableEqualToJson([Product.watchApp],"[\"watchApp\"]")
        assertCodableEqualToJson([Product.watch2App],"[\"watch2App\"]")
        assertCodableEqualToJson([Product.watchExtension],"[\"watchExtension\"]")
        assertCodableEqualToJson([Product.watch2Extension],"[\"watch2Extension\"]")
        assertCodableEqualToJson([Product.tvExtension],"[\"tvExtension\"]")
        assertCodableEqualToJson([Product.messagesApplication],"[\"messagesApplication\"]")
        assertCodableEqualToJson([Product.messagesExtension],"[\"messagesExtension\"]")
        assertCodableEqualToJson([Product.stickerPack],"[\"stickerPack\"]")
    }
}
