---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# ترحيل مشروع Xcode {#migrate-an-xcode-project}

ما لم <LocalizedLink href="/guides/features/projects/adoption/new-project">تنشئ
مشروعًا جديدًا باستخدام Tuist</LocalizedLink>، وفي هذه الحالة يتم تكوين كل شيء
تلقائيًا، فسيتعين عليك تعريف مشاريع Xcode باستخدام عناصر Tuist الأساسية. مدى
صعوبة هذه العملية يعتمد على مدى تعقيد مشاريعك.

كما تعلمون، قد تصبح مشاريع Xcode فوضوية ومعقدة بمرور الوقت: مجموعات لا تتطابق مع
بنية الدليل، وملفات مشتركة بين الأهداف، أو مراجع ملفات تشير إلى ملفات غير موجودة
(على سبيل المثال). كل هذه التعقيدات المتراكمة تجعل من الصعب علينا توفير أمر يضمن
ترحيل المشروع بشكل موثوق.

علاوة على ذلك، يعد الترحيل اليدوي تمرينًا ممتازًا لتنظيف مشاريعك وتبسيطها. لن
يكون المطورون في مشروعك ممتنين لذلك فحسب، بل سيكون Xcode أيضًا، الذي سيقوم
بمعالجتها وفهرستها بشكل أسرع. بمجرد اعتماد Tuist بالكامل، سيضمن أن المشاريع
محددة بشكل متسق وأنها تظل بسيطة.

بهدف تسهيل هذا العمل، نقدم لك بعض الإرشادات بناءً على التعليقات التي تلقيناها من
المستخدمين.

## إنشاء هيكل المشروع {#create-project-scaffold}

أولاً، قم بإنشاء هيكل لمشروعك باستخدام ملفات Tuist التالية:

:::: مجموعة الرموز

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` هو ملف البيان الذي ستحدد فيه مشروعك، و `Package.swift` هو ملف
البيان الذي ستحدد فيه التبعيات. ملف `Tuist.swift` هو المكان الذي يمكنك فيه تحديد
إعدادات Tuist على نطاق المشروع لمشروعك.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
لمنع حدوث تعارض مع مشروع Xcode الحالي، نوصي بإضافة اللاحقة `-Tuist` إلى اسم
المشروع. يمكنك حذفها بمجرد الانتهاء من ترحيل مشروعك بالكامل إلى Tuist.
<!-- -->
:::

## قم ببناء واختبار مشروع Tuist في CI {#build-and-test-the-tuist-project-in-ci}

لضمان صحة ترحيل كل تغيير، نوصي بتوسيع نطاق التكامل المستمر لإنشاء واختبار
المشروع الذي أنشأته Tuist من ملف البيان الخاص بك:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## استخرج إعدادات إنشاء المشروع إلى ملفات `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

استخرج إعدادات البناء من المشروع إلى ملف `.xcconfig` لجعل المشروع أكثر بساطة
وسهولة في الترحيل. يمكنك استخدام الأمر التالي لاستخراج إعدادات البناء من المشروع
إلى ملف `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

ثم قم بتحديث ملف `Project.swift` للإشارة إلى ملف `.xcconfig` الذي أنشأته للتو:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

ثم قم بتوسيع خط أنابيب التكامل المستمر لتشغيل الأمر التالي للتأكد من أن
التغييرات على إعدادات البناء يتم إجراؤها مباشرة على ملفات `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## استخراج تبعيات الحزمة {#extract-package-dependencies}

استخرج جميع تبعيات مشروعك إلى ملف `Tuist/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

::: tip PRODUCT TYPES
<!-- -->
يمكنك تجاوز نوع المنتج لحزمة معينة عن طريق إضافته إلى قاموس `productTypes` في
بنية `PackageSettings`. بشكل افتراضي، يفترض Tuist أن جميع الحزم هي أطر عمل
ثابتة.
<!-- -->
:::


## تحديد ترتيب الترحيل {#determine-the-migration-order}

نوصي بترحيل الأهداف من الأكثر اعتمادًا إلى الأقل اعتمادًا. يمكنك استخدام الأمر
التالي لإدراج أهداف مشروع ما، مرتبة حسب عدد التبعيات:

```bash
tuist migration list-targets -p Project.xcodeproj
```

ابدأ في ترحيل الأهداف من أعلى القائمة، لأنها الأكثر أهمية.


## ترحيل الأهداف {#migrate-targets}

قم بترحيل الأهداف واحدة تلو الأخرى. نوصي بإجراء طلب سحب لكل هدف للتأكد من مراجعة
التغييرات واختبارها قبل دمجها.

### استخرج إعدادات البنية المستهدفة إلى ملفات `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

كما فعلت مع إعدادات إنشاء المشروع، قم باستخراج إعدادات الإنشاء المستهدفة إلى ملف
`.xcconfig` لجعل الهدف أكثر بساطة وسهولة في الترحيل. يمكنك استخدام الأمر التالي
لاستخراج إعدادات الإنشاء من الهدف إلى ملف `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### حدد الهدف في ملف `Project.swift` {#define-the-target-in-the-projectswift-file}

حدد الهدف في `Project.targets`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
إذا كان الهدف يحتوي على هدف اختبار مرتبط، فيجب عليك تعريفه في ملف
`Project.swift` مع تكرار نفس الخطوات.
<!-- -->
:::

### تحقق من صحة الترحيل المستهدف {#validate-the-target-migration}

قم بتشغيل `tuist generate` متبوعًا بـ `xcodebuild build` للتأكد من إنشاء
المشروع، و `tuist test` للتأكد من اجتياز الاختبارات. بالإضافة إلى ذلك، يمكنك
استخدام [xcdiff](https://github.com/bloomberg/xcdiff) لمقارنة مشروع Xcode الذي
تم إنشاؤه بالمشروع الحالي للتأكد من صحة التغييرات.

### كرر {#repeat}

كرر ذلك حتى يتم ترحيل جميع الأهداف بالكامل. بمجرد الانتهاء، نوصي بتحديث خطوط
أنابيب CI و CD لإنشاء المشروع واختباره باستخدام `tuist generate` متبوعًا بـ
`xcodebuild build` و `tuist test`.

## استكشاف الأخطاء وإصلاحها {#استكشاف الأخطاء وإصلاحها}

### أخطاء التجميع بسبب الملفات المفقودة. {#compilation-errors-due-to-missing-files}

إذا لم تكن الملفات المرتبطة بأهداف مشروع Xcode موجودة جميعها في دليل نظام
الملفات الذي يمثل الهدف، فقد ينتهي بك الأمر بمشروع لا يمكن تجميعه. تأكد من أن
قائمة الملفات بعد إنشاء المشروع باستخدام Tuist تتطابق مع قائمة الملفات في مشروع
Xcode، واغتنم الفرصة لمواءمة بنية الملفات مع بنية الهدف.
