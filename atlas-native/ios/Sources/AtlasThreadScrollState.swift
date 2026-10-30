import Combine
import Foundation
import SwiftUI

struct AtlasThreadScrollMetrics: Equatable {
    let height: CGFloat
    let bottom: CGFloat
    let viewport: CGFloat
    var inset: CGFloat = 0
    var offset: CGFloat { height - bottom }
    var atBottom: Bool { abs(bottom - min(height, viewport)) <= 20 }
}

final class AtlasThreadScrollState: ObservableObject {
    @Published var following = true
    // iOS 17 has no scroll-phase API; nil uses stable-layout displacement instead.
    var userScrolling: Bool?
    private var previous: AtlasThreadScrollMetrics?
    private var baseline: CGFloat?
    private var settlingLayout = false

    func reset() {
        if !following { following = true }
        userScrolling = nil
        previous = nil
        baseline = nil
        settlingLayout = false
    }

    func update(_ metrics: AtlasThreadScrollMetrics) {
        let layoutChanged = previous?.height != metrics.height || previous?.viewport != metrics.viewport
            || previous?.inset != metrics.inset
        previous = metrics
        if layoutChanged {
            baseline = metrics.offset
            settlingLayout = following
        }
        let origin = max(baseline ?? metrics.offset, metrics.offset)
        let movedUp = metrics.offset < origin - 1
        baseline = movedUp ? metrics.offset : origin
        if metrics.atBottom {
            if !following { following = true }
            settlingLayout = false
        } else if userScrolling == true || (userScrolling == nil && !settlingLayout && !layoutChanged && movedUp) {
            if following { following = false }
            settlingLayout = false
        }
    }
}

struct AtlasThreadScrollPreference: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() }
}

struct AtlasThreadScrollObserver: ViewModifier {
    @Binding var messageID: String?
    let anchor: UnitPoint
    let following: Bool
    let latest: AtlasThreadMessage?
    let activity: String?
    let update: (AtlasThreadScrollMetrics) -> Void
    let interaction: (Bool?) -> Void
    @State private var viewportHeight: CGFloat = 0

    private struct FollowUpdate: Equatable {
        let latest: AtlasThreadMessage?
        let activity: String?
        let height: CGFloat
        let following: Bool
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            Group {
                if #available(iOS 18.0, macOS 15.0, *) {
                    content
                        .onScrollGeometryChange(for: AtlasThreadScrollMetrics.self) { geometry in
                            AtlasThreadScrollMetrics(height: geometry.contentSize.height + geometry.contentInsets.top
                                                        + geometry.contentInsets.bottom,
                                                     bottom: geometry.contentSize.height - geometry.contentOffset.y
                                                        + geometry.contentInsets.bottom,
                                                     viewport: geometry.containerSize.height,
                                                     inset: geometry.contentInsets.top + geometry.contentInsets.bottom)
                        } action: { _, metrics in
                            update(metrics)
                            viewportHeight = max(0, metrics.viewport - metrics.inset)
                        }
                        .onScrollPhaseChange { _, phase in
                            interaction(phase == .interacting || phase == .decelerating)
                            if phase == .interacting { messageID = nil }
                        }
                        .onAppear { interaction(false) }
                } else {
                    GeometryReader { viewport in
                        content
                            .onPreferenceChange(AtlasThreadScrollPreference.self) { bounds in
                                if let bounds {
                                    update(AtlasThreadScrollMetrics(height: bounds.height,
                                                                    bottom: bounds.maxY - viewport.frame(in: .global).minY,
                                                                    viewport: viewport.size.height))
                                }
                            }
                            .simultaneousGesture(DragGesture(minimumDistance: 1)
                                .onChanged { _ in interaction(true); messageID = nil }
                                .onEnded { _ in interaction(nil) })
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        viewportHeight = $0
                    }
                }
            }
            // Scroll after layout commits, not from inside geometry feedback.
            .task(id: FollowUpdate(latest: latest, activity: activity, height: viewportHeight, following: following)) {
                if following, latest != nil { proxy.scrollTo("thread-latest", anchor: .bottom) }
            }
            .onChange(of: messageID) { _, id in
                if let id { proxy.scrollTo(id, anchor: anchor) }
            }
        }
    }
}
