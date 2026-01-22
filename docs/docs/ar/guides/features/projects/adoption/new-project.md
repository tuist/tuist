---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# إنشاء مشروع جديد {#create-a-new-project}

الطريقة الأسهل لبدء مشروع جديد باستخدام Tuist هي استخدام الأمر `tuist init`.
يطلق هذا الأمر واجهة CLI تفاعلية ترشدك خلال إعداد مشروعك. عند المطالبة، تأكد من
تحديد الخيار لإنشاء "مشروع مُنشأ".

يمكنك بعد ذلك <LocalizedLink href="/guides/features/projects/editing">تحرير
المشروع</LocalizedLink> بتشغيل `tuist edit` ، وسيفتح Xcode مشروعًا يمكنك تحريره.
أحد الملفات التي يتم إنشاؤها هو `Project.swift` ، والذي يحتوي على تعريف مشروعك.
إذا كنت على دراية بـ Swift Package Manager، فاعتبره `Package.swift` ولكن بلغة
مشاريع Xcode.

:::: مجموعة الرموز
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

:::: المعلومات
<!-- -->
نحن نحافظ عمدًا على قائمة القوالب المتاحة قصيرة لتقليل عبء الصيانة. إذا كنت ترغب
في إنشاء مشروع لا يمثل تطبيقًا، على سبيل المثال إطار عمل، يمكنك استخدام `tuist
init` كنقطة انطلاق ثم تعديل المشروع الذي تم إنشاؤه ليناسب احتياجاتك.
<!-- -->
:::

## إنشاء مشروع يدويًا {#manually-creating-a-project}

بدلاً من ذلك، يمكنك إنشاء المشروع يدويًا. نوصي بالقيام بذلك فقط إذا كنت على
دراية بـ Tuist ومفاهيمه. أول شيء عليك القيام به هو إنشاء دلائل إضافية لهيكل
المشروع:

```bash
mkdir MyFramework
cd MyFramework
```

ثم قم بإنشاء ملف `Tuist.swift` ، والذي سيقوم بتكوين Tuist ويستخدمه Tuist لتحديد
الدليل الجذر للمشروع، وملف `Project.swift` ، حيث سيتم الإعلان عن مشروعك:

:::: مجموعة الرموز
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

:::: تحذير
<!-- -->
يستخدم Tuist الدليل `Tuist/` لتحديد جذر مشروعك، ومن هناك يبحث عن ملفات البيانات
الأخرى التي تجمع الدلائل. نوصي بإنشاء هذه الملفات باستخدام محرر من اختيارك، ومن
ذلك الحين فصاعدًا، يمكنك استخدام `tuist edit` لتحرير المشروع باستخدام Xcode.
<!-- -->
:::
