import Foundation

protocol Printing: AnyObject {
    func print(_ text: String)
}

class Printer: Printing {
    func print(_ text: String) {
        Swift.print(text)
    }
}
