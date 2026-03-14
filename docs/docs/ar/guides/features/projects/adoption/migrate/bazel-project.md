---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# ترحيل مشروع Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) هو نظام بناء أطلقته Google كمصدر مفتوح في عام 2015.
إنه أداة قوية تسمح لك ببناء واختبار برامج من أي حجم، بسرعة وموثوقية. تستخدمه بعض
المؤسسات الكبيرة مثل
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)
و[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
و[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)، ومع ذلك، فإنه يتطلب
استثمارًا مسبقًا (أي تعلم التكنولوجيا) واستثمارًا مستمرًا (أي مواكبة تحديثات
Xcode) لتقديمه وصيانته. في حين أن هذا يناسب بعض المؤسسات التي تعامله على أنه
مسألة شاملة، فقد لا يكون الخيار الأنسب لمؤسسات أخرى ترغب في التركيز على تطوير
منتجاتها. على سبيل المثال، رأينا مؤسسات قام فريق منصة iOS فيها بتطبيق Bazel
واضطر إلى التخلي عنه بعد مغادرة المهندسين الذين قادوا هذه المبادرة الشركة. ويعد
موقف Apple من الترابط القوي بين Xcode ونظام البناء عاملاً آخر يجعل من الصعب
صيانة مشاريع Bazel بمرور الوقت.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
بدلاً من محاربة Xcode ومشاريع Xcode، يتبنى Tuist هذه المنصة. إنها نفس المفاهيم
(مثل الأهداف والمخططات وإعدادات البناء)، ولغة مألوفة (أي Swift)، وتجربة بسيطة
وممتعة تجعل صيانة المشاريع وتوسيع نطاقها مهمة الجميع وليس فقط فريق منصة iOS.
<!-- -->
:::

## القواعد {#rules}

يستخدم Bazel القواعد لتحديد كيفية إنشاء البرامج واختبارها. تُكتب القواعد بلغة
[Starlark](https://github.com/bazelbuild/starlark)، وهي لغة تشبه لغة Python.
يستخدم Tuist لغة Swift كلغة تكوين، مما يوفر للمطورين سهولة استخدام ميزات الإكمال
التلقائي والتحقق من النوع والتحقق من الصحة في Xcode. على سبيل المثال، تصف
القاعدة التالية كيفية إنشاء مكتبة Swift في Bazel:

:::: مجموعة الرموز
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

إليك مثال آخر يقارن بين كيفية تعريف اختبارات الوحدة في Bazel و Tuist:

:::: مجموعة الرموز
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)
```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## تبعيات Swift Package Manager {#swift-package-manager-dependencies}

في Bazel، يمكنك استخدام المكون الإضافي
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
لاستخدام حزم Swift كاعتمادات. يتطلب المكون الإضافي ملف `Package.swift` كمصدر
موثوق للاعتمادات. واجهة Tuist مشابهة لواجهة Bazel في هذا الصدد. يمكنك استخدام
الأمر `tuist install` لحل وسحب تبعيات الحزمة. بعد اكتمال الحل، يمكنك بعد ذلك
إنشاء المشروع باستخدام الأمر `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## إنشاء المشروع {#project-generation}

توفر المجتمع مجموعة من القواعد،
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)،
لإنشاء مشاريع Xcode من المشاريع المعلنة في Bazel. على عكس Bazel، حيث تحتاج إلى
إضافة بعض التكوينات إلى ملف BUILD` الخاص بـ `، لا يتطلب Tuist أي تكوين على
الإطلاق. يمكنك تشغيل `tuist generate` في الدليل الجذر لمشروعك، وسيقوم Tuist
بإنشاء مشروع Xcode لك.
