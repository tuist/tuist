import Library
// Importing the static Objective-C modules directly forces the compiler to build
// the `NestedObjC` / `NestedObjCKit` clang modules while they are consumed behind
// the cached dynamic `Library`. Building `NestedObjCKit` pulls in `NestedObjC` (a
// cross-module import), which is where the "import of shadowed module" failure
// surfaced when the same module was reachable through two module maps.
import NestedObjC
import NestedObjCKit

let feature = NestedFeature()
feature.anchor = NestedAnchor()
print(feature.anchor?.trackingState.rawValue ?? 0)
print(Library.trackingState())
