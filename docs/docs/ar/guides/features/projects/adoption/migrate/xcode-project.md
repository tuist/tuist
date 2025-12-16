---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# ترحيل مشروع Xcode {#migrate-an-xcode-project}

ما لم تقم <LocalizedLink href="/guides/features/projects/adoption/new-project">
بإنشاء مشروع جديد باستخدام تويست </LocalizedLink>، وفي هذه الحالة ستحصل على كل
شيء مهيأ تلقائيًا، سيكون عليك تحديد مشاريع Xcode الخاصة بك باستخدام أساسيات
تويست. يعتمد مدى ملل هذه العملية على مدى تعقيد مشاريعك.

كما تعلم على الأرجح، يمكن أن تصبح مشاريع Xcode فوضوية ومعقدة بمرور الوقت:
مجموعات لا تتطابق مع بنية الدليل، أو ملفات مشتركة بين الأهداف، أو مراجع ملفات
تشير إلى ملفات غير موجودة (على سبيل المثال لا الحصر). كل هذه التعقيدات المتراكمة
تجعل من الصعب علينا توفير أمر يقوم بترحيل المشروع بشكل موثوق.

علاوة على ذلك، فإن الترحيل اليدوي هو تمرين ممتاز لتنظيف مشاريعك وتبسيطها. لن
يكون المطورون في مشروعك وحدهم ممتنين لذلك، بل سيكون Xcode أيضًا ممتنًا لذلك، حيث
سيعمل على معالجتها وفهرستها بشكل أسرع. بمجرد أن تتبنى Tuist بالكامل، ستحرص على
أن يتم تعريف المشاريع بشكل متسق وأن تظل بسيطة.

بهدف تسهيل هذا العمل، نقدم لك بعض الإرشادات بناءً على الملاحظات التي تلقيناها من
المستخدمين.

## إنشاء سقالة مشروع {#إنشاء سقالة مشروع-مشروع-سقالة}

أولاً، قم بإنشاء سقالة لمشروعك باستخدام ملفات Tuist التالية:

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

`Project.swift.swift` هو ملف البيان حيث ستحدد مشروعك، و `Package.swift` هو ملف
البيان حيث ستحدد تبعياتك. ملف `Tuist.swift.swift` هو الملف الذي يمكنك من خلاله
تحديد إعدادات Tuist على نطاق المشروع لمشروعك.

:::: تلميح اسم المشروع مع -TUIST SUFFIX
<!-- -->
لمنع التعارض مع مشروع Xcode الحالي، نوصي بإضافة لاحقة `-Tuist` إلى اسم المشروع.
يمكنك إسقاطها بمجرد ترحيل مشروعك بالكامل إلى Tuist.
<!-- -->
:::

## بناء واختبار مشروع تويست في CI {#build-and-test-the-tuist-project-in-ci}

للتأكد من صحة ترحيل كل تغيير، نوصي بتوسيع نطاق التكامل المستمر لبناء واختبار
المشروع الذي تم إنشاؤه بواسطة Tuist من ملف البيان الخاص بك:

```bash
tuist install
tuist generate
tuist build -- ...{xcodebuild flags} # or tuist test
```

## استخرج إعدادات بناء المشروع إلى ملفات `.xcconfig` {#extract-the-project-build-settings-into-into-cconfig-files}

استخرج إعدادات الإنشاء من المشروع إلى ملف `.xcconfig` لجعل المشروع أكثر مرونة
وأسهل في الترحيل. يمكنك استخدام الأمر التالي لاستخراج إعدادات الإنشاء من المشروع
إلى ملف `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

ثم قم بتحديث ملف `Project.swift.swift` الخاص بك للإشارة إلى ملف `.xcconfig` الذي
قمت بإنشائه للتو:

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

ثم قم بتوسيع خط أنابيب التكامل المستمر لتشغيل الأمر التالي لضمان إجراء التغييرات
على إعدادات الإنشاء مباشرةً إلى ملفات `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## استخراج تبعيات الحزمة {#استخراج تبعيات الحزمة}

استخرج جميع تبعيات مشروعك في ملف `Tuist/Package.swift.swift`:

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

:::: إكرامية أنواع المنتجات
<!-- -->
يمكنك تجاوز نوع المنتج لحزمة معينة عن طريق إضافته إلى قاموس `productTypes` في
`PackageSettings` structure. يفترض تويست افتراضيًا أن جميع الحزم هي أطر عمل
ثابتة.
<!-- -->
:::


## تحديد ترتيب الترحيل {#تحديد-ترتيب-الترحيل}

نوصي بترحيل الأهداف من الأكثر اعتمادًا إلى الأقل اعتمادًا. يمكنك استخدام الأمر
التالي لسرد أهداف مشروع ما، مرتبة حسب عدد التبعيات:

```bash
tuist migration list-targets -p Project.xcodeproj
```

ابدأ بترحيل الأهداف من أعلى القائمة، لأنها الأكثر اعتمادًا عليها.


## ترحيل الأهداف {# ترحيل-الأهداف}

ترحيل الأهداف واحدًا تلو الآخر. نوصي بإجراء طلب سحب لكل هدف لضمان مراجعة
التغييرات واختبارها قبل دمجها.

### استخرج إعدادات البناء الهدف إلى ملفات `.xcconfig` {#extract-the-target-build-settings-into-into-cconfig-files}

كما فعلت مع إعدادات بناء المشروع، استخرج إعدادات بناء الهدف في ملف `.xcconfig`
لجعل الهدف أكثر مرونة وأسهل في الترحيل. يمكنك استخدام الأمر التالي لاستخراج
إعدادات البناء من الهدف إلى ملف `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### قم بتعريف الهدف في ملف `Project.swift.` {#تعريف الهدف في ملف مشروع سويفت }

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

:::: معلومات اختبار الأهداف الاختبارية
<!-- -->
إذا كان للهدف هدف اختبار مرتبط، فيجب عليك تعريفه في ملف `Project.swift.` أيضًا
بتكرار نفس الخطوات.
<!-- -->
:::

### التحقق من صحة الترحيل المستهدف {#التحقق من صحة الترحيل المستهدف}

قم بتشغيل `tuist build` و `tuist test` للتأكد من أن المشروع قد تم إنشاؤه
واختباراته قد نجحت. بالإضافة إلى ذلك، يمكنك استخدام [xcdiff]
(https://github.com/bloomberg/xcdiff) لمقارنة مشروع Xcode الذي تم إنشاؤه مع
المشروع الحالي للتأكد من صحة التغييرات.

### كرر {#كرر}

كرر ذلك حتى يتم ترحيل جميع الأهداف بالكامل. بمجرد الانتهاء من ذلك، نوصي بتحديث
خطوط أنابيب CI و CD الخاصة بك لبناء واختبار المشروع باستخدام الأوامر `tuist
build` و `tuist test` للاستفادة من السرعة والموثوقية التي يوفرها Tuist.

## استكشاف الأخطاء وإصلاحها {#استكشاف الأخطاء وإصلاحها}

### أخطاء التجميع بسبب الملفات المفقودة. {#أخطاء التجميع بسبب الملفات المفقودة}

إذا لم تكن جميع الملفات المرتبطة بأهداف مشروع Xcode الخاص بك متضمنة في دليل نظام
الملفات الذي يمثل الهدف، فقد ينتهي بك الأمر بمشروع لا يتم تجميعه. تأكد من تطابق
قائمة الملفات بعد إنشاء المشروع باستخدام Tuist مع قائمة الملفات في مشروع Xcode،
واغتنم الفرصة لمواءمة بنية الملفات مع بنية الهدف.
