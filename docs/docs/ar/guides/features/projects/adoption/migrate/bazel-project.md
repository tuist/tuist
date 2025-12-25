---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# ترحيل مشروع بازل {#migrate-a-bazel-project}

[Bazel] (https://bazel.build) هو نظام بناء قامت جوجل بفتح مصادره في عام 2015.
وهو أداة قوية تسمح لك ببناء واختبار البرمجيات من أي حجم، بسرعة وموثوقية. تستخدمه
بعض المؤسسات الكبيرة مثل
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)
أو
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
أو [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)، ومع ذلك، فإنه يتطلب
استثمارًا مقدمًا (أي تعلم التكنولوجيا) واستثمارًا مستمرًا (أي مواكبة تحديثات
Xcode) لتقديمه وصيانته. وفي حين أن هذا الأمر مناسب لبعض المؤسسات التي تتعامل معه
على أنه اهتمام شامل، إلا أنه قد لا يكون الأنسب لمؤسسات أخرى تريد التركيز على
تطوير منتجاتها. على سبيل المثال، رأينا مؤسسات قام فريق منصة iOS لديها بتقديم
بازل واضطروا إلى التخلي عنه بعد أن غادر المهندسون الذين قادوا هذا الجهد الشركة.
موقف Apple من الاقتران القوي بين Xcode ونظام الإنشاء هو عامل آخر يجعل من الصعب
الحفاظ على مشاريع Bazel مع مرور الوقت.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
بدلًا من محاربة Xcode ومشاريع Xcode، يحتضن تويست ذلك. إنها نفس المفاهيم (مثل
الأهداف والمخططات وإعدادات الإنشاء)، ولغة مألوفة (أي سويفت)، وتجربة بسيطة وممتعة
تجعل صيانة المشاريع وتوسيع نطاقها مهمة الجميع وليس فقط فريق منصة iOS.
<!-- -->
:::

## القواعد {#rules}

يستخدم بازل قواعد لتحديد كيفية بناء واختبار البرمجيات. تتم كتابة القواعد بلغة
[Starlark] (https://github.com/bazelbuild/starlark)، وهي لغة شبيهة بلغة بايثون.
يستخدم تويست لغة سويفت كلغة تكوين، والتي توفر للمطورين سهولة استخدام ميزات
الإكمال التلقائي والتحقق من النوع والتحقق من صحة برمجيات Xcode. على سبيل المثال،
تصف القاعدة التالية كيفية بناء مكتبة سويفت في بازل:

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

إليك مثال آخر ولكن بمقارنة كيفية تعريف اختبارات الوحدة في بازل وتويست:

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


## تبعيات مدير حزم Swift Package Manager {#swift-package-manager-dependencies}

في Bazel، يمكنك استخدام
[`rules_swift_swift_package_manager`]](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
المكوّن الإضافي لاستخدام حزم سويفت كتبعيات. يتطلب المكون الإضافي `Package.swift`
كمصدر للحقيقة للتبعيات. واجهة تويست مشابهة لواجهة بازل بهذا المعنى. يمكنك
استخدام الأمر `tuist install` لحل وسحب تبعيات الحزمة. بعد اكتمال عملية الحل،
يمكنك بعد ذلك إنشاء المشروع باستخدام الأمر `tuist gener`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## توليد المشاريع {#project-generation}

يوفّر المجتمع مجموعة من القواعد،
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)،
لتوليد مشاريع Xcode من مشاريع بازل المعلنة. على عكس Bazel، حيث تحتاج إلى إضافة
بعض التهيئة إلى ملف `BUILD` ، لا يتطلب Tuist أي تهيئة على الإطلاق. يمكنك تشغيل
`tuist gener` في الدليل الجذر لمشروعك، وسيقوم Tuist بإنشاء مشروع Xcode لك.
