#import <Foundation/Foundation.h>

// Imports another module with the framework-prefixed form
// `#import <NestedObjC/Anchor.h>`. This cross-module import is what makes the
// compiler build `NestedObjC` while building `NestedObjCKit`, which surfaced the
// "import of shadowed module" failure when the same module was reachable through
// two module maps.
#import <NestedObjC/Anchor.h>

@interface NestedFeature : NSObject
@property(nonatomic, strong, nullable) NestedAnchor *anchor;
@end
