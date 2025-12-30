---
title: "Tuist 3.33.0 and XcodeProj-native support for Swift Macros"
category: "product"
tags: ["Swift", "XcodeProj", "Xcode"]
excerpt: "We released a new version of Tuist, which includes XcodeProj-native support for Swift Macros"
author: pepicrft
---

When [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) were introduced, there was widespread excitement about the possibilities they enabled. Developers could now write Swift code that would modify other Swift code at compile-time. To support this feature, Apple chose to adopt [Swift Packages](https://developer.apple.com/documentation/xcode/swift-packages) as a bundle and distribution format.

While this integration made sense on a smaller scale, **it also inherited the same challenges as Swift Packages** and Xcode's proposal for their integration when applied to large projects. These challenges included getting invalidated during Xcode cleaning, leaving Xcode in an invalid state after manually cleaning derived data, and requiring the compilation of transitive dependencies during clean builds.

Tuist addressed these challenges by integrating dependencies using Xcode projects and their primitives. In essence, Tuist **converted packages into standard targets and projects and then added the necessary links**. This approach combined the best aspects of the Swift Package Manager and [CocoaPods](https://cocoapods.org) worlds, providing access to a vibrant ecosystem of Swift Packages while integrating them in a way that gave developers the control and flexibility needed at a larger scale. Additionally, it offered the added benefit of being cacheable as binaries.

While this approach worked well for packages used at runtime by the targets, a question arose: **could the same be done for Swift Macros?** I'm pleased to share that the answer is yes, and it feels truly magical. It's part of the new release of Tuist, [Tuist 3.33.0](https://github.com/tuist/tuist/releases/tag/3.33.0)

In essence, **a Swift Macro is a combination of a static and an executable.** The former represents the public interface of the Swift Macro, and its module must be visible to the module depending on the macro. The latter contains the actual logic of the macro and needs to be referenced through a Swift compiler flag when compiling the target that depends on the macro. By converting these elements into XcodeProj targets and adding the necessary glue code, Swift Macros can work just like any other standard XcodeProj target. Isn't that cool? We'll soon add support for caching them because *who wants to recompile those dependencies every time if the code rarely changes?*

If you need assistance with integrating Swift Macros into your project, you can refer to [this project as a reference](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_framework_with_native_swift_macro). Please give it a try, and if something doesn't work as expected, don't hesitate to let us know.
