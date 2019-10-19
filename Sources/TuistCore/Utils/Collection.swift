extension Collection where Element: Equatable {
    
    public func doesNotContain(_ element: Element) -> Bool {
        return first(where: { element == $0 }) == nil
    }
    
}
