import XcodeGraph

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { name }
}
