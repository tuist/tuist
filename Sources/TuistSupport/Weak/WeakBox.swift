import Foundation

public class WeakBox<Element: AnyObject> {
    public weak var value: Element?
    public init(_ value: Element) {
        self.value = value
    }
}
