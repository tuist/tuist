---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# التبعيات {#dependencies}

عندما ينمو مشروع ما، من الشائع تقسيمه إلى أهداف متعددة لمشاركة التعليمات
البرمجية وتحديد الحدود وتحسين أوقات الإنشاء. الأهداف المتعددة تعني تحديد
التبعيات فيما بينها لتكوين رسم بياني للتبعية **** ، والذي قد يتضمن تبعيات خارجية
أيضًا.

## الرسوم البيانية المشفرة برموز XProj {#xcodeprojcodified-graphs}

نظرًا لتصميم Xcode و XcodeProj، يمكن أن تكون صيانة الرسم البياني للتبعية مهمة
شاقة وعرضة للأخطاء. إليك بعض الأمثلة على المشاكل التي قد تواجهها:

- نظرًا لأن نظام بناء Xcode يُخرج جميع منتجات المشروع في نفس الدليل في البيانات
  المشتقة، فقد تتمكن الأهداف من استيراد منتجات لا ينبغي لها أن تستوردها. قد تفشل
  عمليات التجميع في CI، حيث تكون البنيات النظيفة أكثر شيوعًا، أو لاحقًا عند
  استخدام تكوين مختلف.
- يجب نسخ التبعيات الديناميكية المتعدية لهدف ما إلى أي من الدلائل التي تشكل
  جزءًا من إعداد الإنشاء `LD_RUNPATH_SEARCH_PATHS`. إذا لم تكن كذلك، فلن يتمكن
  الهدف من العثور عليها في وقت التشغيل. من السهل التفكير في هذا الأمر وإعداده
  عندما يكون الرسم البياني صغيرًا، لكنه يصبح مشكلة مع نمو الرسم البياني.
- عندما يقوم الهدف بربط [XCFramework] [XCFramework] [1] ثابت، يحتاج الهدف إلى
  مرحلة بناء إضافية لـ Xcode لمعالجة الحزمة واستخراج الثنائية المناسبة للمنصة
  والبنية الحالية. لا تُضاف مرحلة الإنشاء هذه تلقائيًا، ومن السهل نسيان إضافتها.

ما سبق مجرد أمثلة قليلة، ولكن هناك العديد من الأمثلة الأخرى التي واجهناها على مر
السنين. تخيل لو أنك طلبت من فريق من المهندسين الحفاظ على الرسم البياني للتبعية
والتأكد من صلاحيته. أو الأسوأ من ذلك، أن يتم حل التعقيدات في وقت الإنشاء بواسطة
نظام بناء مغلق المصدر لا يمكنك التحكم فيه أو تخصيصه. هل يبدو مألوفاً؟ هذا هو
النهج الذي اتبعته Apple مع Xcode و XcodeProj والذي ورثه مدير حزم Swift.

نحن نعتقد بقوة أن الرسم البياني للتبعية يجب أن يكون **صريحًا** و **ثابتًا** لأنه
عندها فقط يمكن أن يكون **التحقق من صحته** و **الأمثل**. مع تويست، أنت تركز على
وصف ما يعتمد على ماذا، ونحن نهتم بالباقي. يتم تجريد التعقيدات وتفاصيل التنفيذ
بعيدًا عنك.

ستتعلم في الأقسام التالية كيفية الإعلان عن التبعيات في مشروعك.

::: tip التحقق من صحة الرسم البياني
يتحقق تويست من صحة الرسم البياني عند إنشاء المشروع للتأكد من عدم وجود دورات وأن
جميع التبعيات صالحة. وبفضل هذا، يمكن لأي فريق المشاركة في تطوير الرسم البياني
للتبعية دون القلق بشأن كسره.
:::

## التبعيات المحلية {#local-dependencies}

يمكن أن تعتمد الأهداف على أهداف أخرى في نفس المشروع أو في مشاريع مختلفة، وعلى
الثنائيات. عند إنشاء هدف `الهدف` ، يمكنك تمرير الوسيطة `التبعيات` مع أي من
الخيارات التالية:

- `الهدف`: يعلن تبعية مع هدف داخل نفس المشروع.
- `المشروع`: يعلن تبعية مع هدف في مشروع مختلف.
- `الإطار`: يعلن تبعية مع إطار عمل ثنائي.
- `مكتبة`: يعلن تبعية مع مكتبة ثنائية.
- `XCFramework`: يعلن تبعية مع ثنائي XCFramework XCFramework.
- `SDK`: يعلن تبعية مع SDK النظام.
- `XCTest`: يعلن التبعية مع XCTest.

::: info عن شروط التبعية
يقبل كل نوع تبعية خيار `شرط` لربط التبعية بشكل مشروط بناءً على النظام الأساسي.
بشكل افتراضي، يربط التبعية لجميع المنصات التي يدعمها الهدف.
:::

## التبعيات الخارجية {#external-dependencies}

يسمح لك تويست أيضًا بإعلان التبعيات الخارجية في مشروعك.

### حزم سويفت {#swift-packages}

حزم سويفت هي طريقتنا الموصى بها للإعلان عن التبعيات في مشروعك. يمكنك دمجها
باستخدام آلية التكامل الافتراضية لـ Xcode أو باستخدام التكامل المستند إلى
XcodeProj الخاص بـ Tuist.

#### التكامل المستند إلى XcodeProj من تويست {#tuists-xcodeproj-based-integration}

على الرغم من أن التكامل الافتراضي لـ Xcode هو الأكثر ملاءمة، إلا أنه يفتقر إلى
المرونة والتحكم المطلوبين للمشاريع المتوسطة والكبيرة. للتغلب على ذلك، يقدم Tuist
تكاملًا قائمًا على XcodeProj يسمح لك بدمج حزم Swift في مشروعك باستخدام أهداف
XcodeProj. وبفضل ذلك، لا يمكننا فقط منحك مزيدًا من التحكم في التكامل، بل يمكننا
أيضًا جعله متوافقًا مع عمليات سير العمل مثل
<LocalizedLink href="/guides/features/cache">التخزين المؤقت</LocalizedLink> و <LocalizedLink href="/guides/features/test/selective-testing">عمليات التشغيل الاختبار الانتقائي</LocalizedLink>.

من المرجح أن يستغرق تكامل XcodeProj المزيد من الوقت لدعم ميزات Swift Package
الجديدة أو التعامل مع المزيد من تكوينات الحزمة. ومع ذلك، فإن منطق التعيين بين
حزم Swift Packages وأهداف XcodeProj مفتوح المصدر ويمكن للمجتمع المساهمة فيه. هذا
على عكس التكامل الافتراضي لـ Xcode، وهو مغلق المصدر وتحتفظ به Apple.

لإضافة تبعيات خارجية، سيتعين عليك إنشاء `Package.swift` إما ضمن `تويست/` أو في
جذر المشروع.

:::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```

::::

::: tip إعدادات الحزمة
يسمح لك مثيل `PackageSettings` المغلف بتوجيه مترجم بتكوين كيفية دمج الحزم. على
سبيل المثال، في المثال أعلاه يُستخدم لتجاوز نوع المنتج الافتراضي المستخدم للحزم.
بشكل افتراضي، يجب ألا تحتاج إليه.
:::

> [!هام] تكوينات البناء المخصص إذا كان مشروعك يستخدم تكوينات بناء مخصصة (تكوينات
> أخرى غير القياسية `التصحيح` و `الإصدار`)، يجب عليك تحديدها في
> `PackageSettings` باستخدام `baseSettings`. تحتاج التبعيات الخارجية إلى معرفة
> تكوينات مشروعك للبناء بشكل صحيح. على سبيل المثال
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> انظر [#8345] (https://github.com/tuist/tuist/issues/8345) لمزيد من التفاصيل.

إن ملف `Package.swift.swift` هو مجرد واجهة للإعلان عن التبعيات الخارجية، لا شيء
آخر. لهذا السبب لا تحدد أي أهداف أو منتجات في الحزمة. بمجرد تحديد التبعيات،
يمكنك تشغيل الأمر التالي لحل التبعيات وسحبها إلى دليل `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

كما لاحظتم، فإننا نتبع نهجًا مشابهًا لـ [CocoaPods] (https://cocoapods.org)'،
حيث يكون حل التبعيات أمرًا خاصًا به. وهذا يمنح المستخدمين التحكم في الوقت الذي
يرغبون فيه حل التبعيات وتحديثها، ويسمح بفتح Xcode في المشروع وتجهيزه للتجميع.
هذا هو المجال الذي نعتقد أن تجربة المطورين التي يوفرها تكامل Apple مع مدير حزم
Swift تتدهور بمرور الوقت مع نمو المشروع.

من أهداف مشروعك، يمكنك بعد ذلك الرجوع إلى تلك التبعيات باستخدام نوع التبعيات
`TargetDependency.external`:

:::: مجموعة الرموز
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info لم يتم توليد أي خطط للحزم الخارجية
لا يتم إنشاء المخططات **المخططات** تلقائيًا لمشاريع حزمة سويفت للحفاظ على قائمة
المخططات نظيفة. يمكنك إنشاؤها عبر واجهة مستخدم Xcode.
:::

#### التكامل الافتراضي ل Xcode {#xxcodes-default-integration}

إذا كنت ترغب في استخدام آلية التكامل الافتراضية لـ Xcode، يمكنك تمرير القائمة
`الحزم` عند إنشاء مشروع:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

ثم قم بالرجوع إليها من أهدافك:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

بالنسبة لوحدات ماكرو سويفت ومكونات أداة الإنشاء الإضافية، ستحتاج إلى استخدام
النوعين `.macro` و `.plugin` على التوالي.

::: warning المكونات الإضافية لأداة بناء SPM
يجب الإعلان عن المكونات الإضافية لأداة بناء SPM باستخدام آلية [التكامل الافتراضي
لـ Xcode] (#xcode-s-default-integration)، حتى عند استخدام [التكامل القائم على
XcodeProj] (#tuist-s-xcodeproj-based-integration) لتبعيات مشروعك.
:::

أحد التطبيقات العملية للمكوّن الإضافي لأداة بناء SPM هو تنفيذ عملية وضع الشيفرة
البرمجية أثناء مرحلة بناء "تشغيل المكونات الإضافية لأداة البناء" في Xcode. في
بيان الحزمة يتم تعريف ذلك على النحو التالي:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

لإنشاء مشروع Xcode مع مكون إضافي لأداة الإنشاء سليم، يجب عليك الإعلان عن الحزمة
في بيان المشروع `حزم المشروع` صفيف ، ثم تضمين حزمة من النوع `.plugin` في تبعيات
الهدف.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### قرطاج {#carthage}

نظرًا لأن [قرطاج] (https://github.com/carthage/carthage) يُخرج `الأطر` أو
`xcframeworks` ، يمكنك تشغيل `carthage update` لإخراج التبعيات في الدليل
`قرطاج/بناء` ثم استخدام `.framework` أو `.xcframework` نوع التبعية المستهدفة
لإعلان التبعية في هدفك. يمكنك تغليف هذا في برنامج نصي يمكنك تشغيله قبل إنشاء
المشروع.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning البناء والاختبار
إذا كنت تقوم ببناء واختبار مشروعك من خلال `tuist build` و `tuist test` ، ستحتاج
بالمثل إلى التأكد من وجود التبعيات التي تم حلها من خلال تشغيل الأمر `carthage
update` قبل تشغيل الأمر `tuist build` أو `tuist test`.
:::

### كبسولات الكاكاو {#cocoapods}

تتوقع [CocoaPods] (https://cocoapods.org) مشروع Xcode لدمج التبعيات. يمكنك
استخدام Tuist لتوليد المشروع، ثم تشغيل `pod install` لدمج التبعيات من خلال إنشاء
مساحة عمل تحتوي على مشروعك وتبعيات Pods. يمكنك تغليف هذا في برنامج نصي يمكنك
تشغيله قبل إنشاء المشروع.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
تبعيات CocoaPods غير متوافقة مع عمليات سير العمل مثل `بناء` أو `اختبار` التي
تقوم بتشغيل `xcodebuild` مباشرة بعد إنشاء المشروع. كما أنها غير متوافقة مع
التخزين المؤقت الثنائي والاختبار الانتقائي لأن منطق البصمات لا يأخذ في الحسبان
تبعيات Pods.
:::

## ثابت أو ديناميكي {#static-or-dynamic}

يمكن ربط الأطر والمكتبات إما بشكل ثابت أو ديناميكي، **وهو خيار له آثار كبيرة على
جوانب مثل حجم التطبيق ووقت الإقلاع**. وعلى الرغم من أهمية هذا القرار، إلا أنه
غالبًا ما يتم اتخاذه دون دراسة كافية.

**القاعدة العامة** هي أنك تريد ربط أكبر عدد ممكن من الأشياء بشكل ثابت في إنشاءات
الإصدار لتحقيق أوقات إقلاع سريعة، وربط أكبر عدد ممكن من الأشياء بشكل ديناميكي في
إنشاءات التصحيح لتحقيق أوقات تكرار سريعة.

التحدي في التغيير بين الربط الثابت والديناميكي في الرسم البياني للمشروع هو أن
هذا ليس بالأمر الهيّن في Xcode لأن التغيير له تأثير متتالي على الرسم البياني
بأكمله (على سبيل المثال لا يمكن أن تحتوي المكتبات على موارد، ولا يلزم تضمين
الأطر الثابتة). حاولت Apple حل المشكلة مع حلول وقت التحويل البرمجي مثل قرار
Swift Package Manager التلقائي بين الربط الثابت والديناميكي، أو [المكتبات
القابلة للدمج]
(https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
ومع ذلك، فإن هذا يضيف متغيرات ديناميكية جديدة إلى الرسم البياني للتجميع، مما
يضيف مصادر جديدة لعدم الحتمية، وربما يتسبب في أن تصبح بعض الميزات مثل Swift
Previews التي تعتمد على الرسم البياني للتجميع غير موثوقة.

لحسن الحظ، يضغط تويست من الناحية المفاهيمية التعقيد المرتبط بالتغيير بين الثابت
والديناميكي ويصنع
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">
حزمة من الملحقات</LocalizedLink> التي تكون قياسية عبر أنواع الربط. بالاقتران مع
<LocalizedLink href="/guides/features/projects/dynamic-configuration"> التكوينات
الديناميكية عبر متغيرات البيئة</LocalizedLink>، يمكنك تمرير نوع الربط في وقت
الاستدعاء، واستخدام القيمة في بياناتك لتعيين نوع المنتج لأهدافك.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

لاحظ أن تويست
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> لا يقوم
بشكل افتراضي بالراحة من خلال التكوين الضمني بسبب تكاليفه</LocalizedLink>. ما
يعنيه هذا هو أننا نعتمد عليك في تحديد نوع الربط وأي إعدادات بناء إضافية مطلوبة
أحيانًا، مثل [`-ObjC` linker flag]
(https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)،
لضمان صحة الثنائيات الناتجة. لذلك، فإن الموقف الذي نتخذه هو تزويدك بالموارد،
عادةً في شكل وثائق، لاتخاذ القرارات الصحيحة.

::: tip مثال: الهيكل القابل للتركيب
حزمة سويفت التي تدمجها العديد من المشاريع هي [البنية القابلة للتركيب]
(https://github.com/pointfreeco/swift-composable-architecture). انظر المزيد من
التفاصيل في [هذا القسم] (#the-composable-architecture).
:::

### سيناريوهات {#scenarios}

هناك بعض السيناريوهات التي لا يكون فيها تعيين الربط بالكامل على ربط ثابت أو
ديناميكي غير ممكن أو فكرة جيدة. فيما يلي قائمة غير حصرية بالسيناريوهات التي قد
تحتاج فيها إلى المزج بين الربط الثابت والديناميكي:

- **التطبيقات ذات الامتدادات:** بما أن التطبيقات وامتداداتها تحتاج إلى مشاركة
  الشيفرة، فقد تحتاج إلى جعل هذه الأهداف ديناميكية. وإلا سينتهي بك الأمر بتكرار
  نفس الشيفرة البرمجية في كل من التطبيق والامتداد، مما يؤدي إلى زيادة حجم
  الشيفرة الثنائية.
- **التبعيات الخارجية المترجمة مسبقًا:** في بعض الأحيان يتم تزويدك بثنائيات
  مجمعة مسبقًا تكون إما ثنائيات ثابتة أو ديناميكية. يمكن تغليف الثنائيات الثابتة
  في أطر أو مكتبات ديناميكية ليتم ربطها ديناميكيًا.

عند إجراء تغييرات على الرسم البياني، سيحلل Tuist الرسم البياني ويعرض تحذيرًا إذا
اكتشف "تأثيرًا جانبيًا ثابتًا". يهدف هذا التحذير إلى مساعدتك في تحديد المشكلات
التي قد تنشأ من ربط هدف ثابت يعتمد بشكل عابر على هدف ثابت من خلال أهداف
ديناميكية. غالبًا ما تظهر هذه الآثار الجانبية على شكل زيادة في حجم الملف
الثنائي، أو في أسوأ الحالات، تعطل وقت التشغيل.

## استكشاف الأخطاء وإصلاحها {#troubleshooting}

### تبعيات Objective-C {#Objectivec-dependencies}

عند دمج تبعيات Objective-C، قد يكون من الضروري تضمين بعض العلامات على الهدف
المستهلك لتجنب أعطال وقت التشغيل كما هو مفصل في [Apple Technical Q&A QA1490]
(https://developer.apple.com/library/archive/qa/qa1490/_index.html).

نظرًا لأن نظام البناء وTuist ليس لديهما أي طريقة لاستنتاج ما إذا كانت العلامة
ضرورية أم لا، وبما أن العلامة تأتي مع آثار جانبية غير مرغوب فيها، فلن يطبق Tuist
تلقائيًا أيًا من هذه العلامات، ولأن Swift Package Manager يعتبر `-ObjC` أن يتم
تضمينها عبر `.unsafeFlag` لا يمكن لمعظم الحزم تضمينها كجزء من إعدادات الربط
الافتراضية عند الحاجة.

يجب على مستهلكي تبعيات Objective-C (أو أهداف Objective-C الداخلية) تطبيق
العلامتين `-ObjC` أو `-force_load` عند الحاجة عن طريق تعيين `OTHER_LDFLAGS` على
الأهداف المستهلكة.

### قاعدة فايربيس ومكتبات جوجل الأخرى {#firebase-other-google-libraries}

على الرغم من قوة مكتبات جوجل مفتوحة المصدر، إلا أنه قد يكون من الصعب دمجها داخل
Tuist لأنها غالبًا ما تستخدم بنية وتقنيات غير قياسية في كيفية بنائها.

فيما يلي بعض النصائح التي قد يكون من الضروري اتباعها لدمج Firebase ومكتبات
Google الأخرى على منصة Apple:

#### تأكد من إضافة `-ObjC` إلى `OTHER_LDFLAGS` {#ensure-objc-is-is-added toother_LDFLAGS}

العديد من مكتبات Google مكتوبة بلغة Objective-C. لهذا السبب، فإن أي هدف مستهلك
سيحتاج إلى تضمين علامة `-ObjC` في إعداد الإنشاء `OTHER_LDFLAGS`. يمكن تعيين هذا
إما في ملف `.xcconfig` أو تحديده يدويًا في إعدادات الهدف ضمن قوائم تويست الخاصة
بك. مثال على ذلك:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

راجع قسم [تبعيات Objective-C] (#objective-c-dependencies) أعلاه لمزيد من
التفاصيل.

#### تعيين نوع المنتج لـ `FBLPromises` إلى إطار عمل ديناميكي {#set-the-product-type-for-fblpromises-to-dynamic-framework}

تعتمد بعض مكتبات Google على `FBLPLPromises` ، وهي مكتبة أخرى من مكتبات Google.
قد تواجه عطلًا يشير إلى `FBLPromises` ، وتبدو مثل هذا:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

من المفترض أن يؤدي تعيين نوع المنتج صراحةً `FBLPromises` إلى `.` في ملف
`Package.swift.` إلى حل المشكلة:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### البنية القابلة للتركيب {#the-composable-architecture}

كما هو موضح [هنا]
(https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
و [قسم استكشاف الأخطاء وإصلاحها] (#troubleshooting)، ستحتاج إلى تعيين إعداد
البناء `OTHER_LDFLAGS` إلى `$ (الموروث) -ObjC` عند ربط الحزم بشكل ثابت، وهو نوع
الربط الافتراضي لـ Tuist. بدلاً من ذلك، يمكنك تجاوز نوع المنتج للحزمة لتكون
ديناميكية. عند الربط بشكل ثابت، عادةً ما تعمل أهداف الاختبار والتطبيق دون أي
مشاكل، ولكن معاينات SwiftUI معطلة. يمكن حل هذه المشكلة عن طريق ربط كل شيء
ديناميكيًا. في المثال أدناه تتم إضافة [المشاركة]
(https://github.com/pointfreeco/swift-sharing) أيضًا كتبعية، حيث أنها غالبًا ما
تُستخدم مع البنية القابلة للتركيب ولها [مزالق التكوين]
(https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)
الخاصة بها.

سيؤدي التكوين التالي إلى ربط كل شيء ديناميكيًا - بحيث تعمل أهداف التطبيق + أهداف
الاختبار ومعاينات SwiftUI.

::: طرف ثابت أو ديناميكي
<!-- -->
لا يوصى دائمًا بالربط الديناميكي. انظر قسم [ثابت أو ديناميكي]
(#static-or-dynamic) لمزيد من التفاصيل. في هذا المثال، يتم ربط جميع التبعيات
ديناميكيًا دون شروط للتبسيط.
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: warning
بدلاً من `استيراد المشاركة` سيكون عليك `استيراد SwiftSharing` بدلاً من ذلك.
:::

### التبعيات الثابتة الانتقالية التي تتسرب من خلال `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

عندما يعتمد إطار عمل ديناميكي أو مكتبة ديناميكية على أخرى ثابتة من خلال `استيراد
StaticSwiftModule` ، يتم تضمين الرموز في `.swiftmodule` من إطار العمل الديناميكي
أو المكتبة، مما قد
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">
يتسبب في فشل التجميع</LocalizedLink>. ولمنع ذلك، سيتعين عليك استيراد التبعية الثابتة باستخدام <LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`الاستيراد الداخلي`</LocalizedLink>:

```swift
internal import StaticModule
```

::: info
تم تضمين مستوى الوصول على الواردات في Swift 6. إذا كنت تستخدم إصدارات أقدم من سويفت، فعليك استخدام <LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_التنفيذ فقط`</LocalizedLink> بدلاً من ذلك:
:::

```swift
@_implementationOnly import StaticModule
```
