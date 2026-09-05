import Library
// Importing `NestedObjC` / `NestedObjCKit` here forces the compiler to build the
// clang modules for the nested-header xcframeworks. With Clang's explicit-modules
// dep scanner, the scan fails if the same module is defined by two module maps —
// which is exactly what happens if the mapper adds vendor `Headers/` on the
// search path while `ProcessXCFramework` has already copied the map into
// `$(BUILT_PRODUCTS_DIR)/include/`.
import NestedObjC
import NestedObjCKit
import StaticWrapper

let feature = NestedFeature()
feature.anchor = NestedAnchor()
print(feature.anchor?.trackingState.rawValue ?? 0)
print(Library.trackingState())
print(StaticWrapper.trackingState())
