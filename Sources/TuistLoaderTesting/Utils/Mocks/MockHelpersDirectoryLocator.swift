import Foundation
import TSCBasic
@testable import TuistLoader

public final class MockHelpersDirectoryLocator: HelpersDirectoryLocating {
    public var locateProjectDescriptionHelpersStub: AbsolutePath?
    public var locateProjectDescriptionHelpersArgs: [AbsolutePath] = []

    public func locateProjectDescriptionHelpers(at: AbsolutePath) -> AbsolutePath? {
        locateProjectDescriptionHelpersArgs.append(at)
        return locateProjectDescriptionHelpersStub
    }
    
    public var locateProjectAutomationHelpersStub: AbsolutePath?
    public var locateProjectAutomationHelpersArgs: [AbsolutePath] = []

    public func locateProjectAutomationHelpers(at: AbsolutePath) -> AbsolutePath? {
        locateProjectAutomationHelpersArgs.append(at)
        return locateProjectAutomationHelpersStub
    }
}
