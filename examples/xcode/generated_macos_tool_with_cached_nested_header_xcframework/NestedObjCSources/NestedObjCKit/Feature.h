#import <Foundation/Foundation.h>

// Mirrors ARCore's ARCoreGeospatial headers, which import the ARCoreGARSession
// module with the framework-prefixed form `#import <ARCoreGARSession/GARAnchor.h>`.
// This cross-module import is what made the compiler build `NestedObjC` while
// building `NestedObjCKit`, surfacing the "import of shadowed module" failure
// when the same module was reachable through two module maps.
#import <NestedObjC/Anchor.h>

@interface NestedFeature : NSObject
@property(nonatomic, strong, nullable) NestedAnchor *anchor;
@end
