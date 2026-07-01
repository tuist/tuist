import NestedObjC
import NestedObjCKit

public enum Library {
    public static func trackingState() -> Int {
        let feature = NestedFeature()
        feature.anchor = NestedAnchor()
        return Int(feature.anchor?.trackingState.rawValue ?? 0)
    }
}
