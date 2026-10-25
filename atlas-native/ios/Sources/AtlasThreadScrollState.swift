import Foundation

struct AtlasThreadScrollMetrics: Equatable {
    let height: CGFloat
    let bottom: CGFloat
    let viewport: CGFloat
    var inset: CGFloat = 0
    var offset: CGFloat { height - bottom }
    var atBottom: Bool { bottom >= 0 && bottom <= viewport + 20 }
}

struct AtlasThreadScrollState {
    var following = true
    // iOS 17 has no scroll-phase API; nil uses stable-layout displacement instead.
    var userScrolling: Bool?
    private var previous: AtlasThreadScrollMetrics?
    private var baseline: CGFloat?

    mutating func update(_ metrics: AtlasThreadScrollMetrics) -> Bool {
        let layoutChanged = previous?.height != metrics.height || previous?.viewport != metrics.viewport
            || previous?.inset != metrics.inset
        previous = metrics
        if layoutChanged { baseline = metrics.offset }
        let origin = max(baseline ?? metrics.offset, metrics.offset)
        let movedUp = metrics.offset < origin - 1
        baseline = movedUp ? metrics.offset : origin
        if metrics.atBottom {
            following = true
        } else if userScrolling == true || (userScrolling == nil && !layoutChanged && movedUp) {
            following = false
        }
        return following && !metrics.atBottom
    }
}
