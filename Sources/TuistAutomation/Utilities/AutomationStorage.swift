import Foundation
import Mockable
import XcodeGraph

@Mockable
/**
 Store for automation-related metadata
 */
public protocol AutomationStoring: AnyObject {
    /// Initial graph before automation mappers were applied
    var initialGraph: Graph? { get set }
}

public final class AutomationStorage: AutomationStoring {
    public init() {}

    public var initialGraph: Graph?
}
