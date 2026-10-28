import Combine
import Foundation
import SwiftUI

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
    private var latestTask: Task<Void, Never>?

    func reset() {
        latestTask?.cancel()
        latestTask = nil
        if !following { following = true }
        userScrolling = nil
        previous = nil
        baseline = nil
        correcting = false
    }

    @MainActor func scheduleLatest(_ action: @escaping () -> Void) {
        guard latestTask == nil else { return }
        latestTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            latestTask = nil
            if following { action() }
        }
    }

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

struct AtlasThreadScrollPreference: PreferenceKey {
    static var defaultValue: AtlasThreadScrollMetrics? { nil }
    static func reduce(value: inout AtlasThreadScrollMetrics?, nextValue: () -> AtlasThreadScrollMetrics?) { value = nextValue() }
}

struct AtlasThreadScrollObserver: ViewModifier {
    let update: (AtlasThreadScrollMetrics) -> Void
    let interaction: (Bool?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: AtlasThreadScrollMetrics.self) { geometry in
                AtlasThreadScrollMetrics(height: geometry.contentSize.height,
                                         bottom: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y,
                                         viewport: geometry.containerSize.height,
                                         inset: geometry.contentInsets.top + geometry.contentInsets.bottom)
            } action: { _, metrics in
                update(metrics)
            }
            .onScrollPhaseChange { _, phase in
                interaction(phase == .interacting || phase == .decelerating)
            }
            .onAppear { interaction(false) }
        } else {
            content.onPreferenceChange(AtlasThreadScrollPreference.self) { metrics in
                if let metrics { update(metrics) }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 1)
                .onChanged { _ in interaction(true) }
                .onEnded { _ in interaction(nil) })
        }
    }
}
