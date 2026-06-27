#import <Foundation/Foundation.h>

// Mirrors ARCore's GARAnchor.h, which re-imports a sibling header using the
// framework-prefixed form `#import <ARCoreGARSession/GARTrackingState.h>`.
// This prefixed self-import only resolves when the xcframework's `Headers`
// root (the parent of the `NestedObjC/` module directory) is on the search
// path, which is exactly what the cached static-objc-behind-dynamic path must
// reconstruct.
#import <NestedObjC/TrackingState.h>

@interface NestedAnchor : NSObject
@property(nonatomic, readonly) NestedTrackingState trackingState;
@end
