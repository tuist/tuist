# App with a custom default configuration settings

This example demonstrates how to set a [default configuration](https://developer.apple.com/library/archive/technotes/tn2339/_index.html#//apple_ref/doc/uid/DTS40014588-CH1-MY_APP_HAS_MULTIPLE_BUILD_CONFIGURATIONS__HOW_DO_I_SET_A_DEFAULT_BUILD_CONFIGURATION_FOR_XCODEBUILD_) in the project settings, which will be used by `xcodebuild` when building from the command-line.

The default build configuration is also used to [visually activate code](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes#Source-Editor) in `#if…#endif` blocks when working with custom configurations other than Debug or Release in Xcode 15 and later.