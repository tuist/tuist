public func platformValue() -> String {
    #if os(iOS)
        "iOS"
    #elseif os(macOS)
        "macOS"
    #else
        "unsupported"
    #endif
}
