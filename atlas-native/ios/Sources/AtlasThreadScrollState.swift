import Combine
import Foundation

struct AtlasThreadScrollMetrics: Equatable {
    let height: CGFloat
    let bottom: CGFloat
    let viewport: CGFloat
    var inset: CGFloat = 0
    var offset: CGFloat { height - bottom }
    var atBottom: Bool { abs(bottom - viewport) <= 20 }
}

final class AtlasThreadScrollState: ObservableObject {
    @Published var following = true
    // iOS 17 has no scroll-phase API; nil uses stable-layout displacement instead.
    var userScrolling: Bool?
    private var previous: AtlasThreadScrollMetrics?
    private var baseline: CGFloat?
    private var correcting = false

    func update(_ metrics: AtlasThreadScrollMetrics) -> Bool {
        let layoutChanged = previous?.height != metrics.height || previous?.viewport != metrics.viewport
            || previous?.inset != metrics.inset
        previous = metrics
        if layoutChanged {
            baseline = metrics.offset
            correcting = following
        }
        let origin = max(baseline ?? metrics.offset, metrics.offset)
        let movedUp = metrics.offset < origin - 1
        baseline = movedUp ? metrics.offset : origin
        if metrics.atBottom {
            if !following { following = true }
            correcting = false
        } else if userScrolling == true || (userScrolling == nil && !correcting && !layoutChanged && movedUp) {
            if following { following = false }
            correcting = false
        }
        return following && !metrics.atBottom
    }
}
