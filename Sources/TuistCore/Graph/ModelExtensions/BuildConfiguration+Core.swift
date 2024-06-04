import Foundation
import XcodeProjectGenerator
import TuistSupport

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { name }
}
