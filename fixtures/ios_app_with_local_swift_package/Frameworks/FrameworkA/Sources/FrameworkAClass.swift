import Foundation
import LibraryA

public class FrameworkAClass {
    public let text: String
    public init() {
        let libraryAClass = LibraryAClass()
        text = "FrameworkAClass::\(libraryAClass.text)"
    }
}
