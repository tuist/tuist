import Library
// Importing the static Objective-C modules directly (as Bird's BirdRiderUI imports
// ARCore) forces the compiler to build the `NestedObjC` / `NestedObjCKit` clang
// modules while they are consumed behind the cached dynamic `Library`. Building
// `NestedObjCKit` pulls in `NestedObjC` (a cross-module import), which is where the
// "import of shadowed module" failure surfaced for ARCore's Geospatial -> GARSession.
import NestedObjC
import NestedObjCKit

let feature = NestedFeature()
feature.anchor = NestedAnchor()
print(feature.anchor?.trackingState.rawValue ?? 0)
print(Library.trackingState())
