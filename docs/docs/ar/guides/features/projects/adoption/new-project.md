---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# إنشاء مشروع جديد {#create-a-new-project}

الطريقة الأكثر مباشرة لبدء مشروع جديد مع تويست هي استخدام الأمر `tuist init`.
يقوم هذا الأمر بتشغيل واجهة CLI تفاعلية ترشدك خلال إعداد مشروعك. عند مطالبتك
بذلك، تأكد من تحديد خيار إنشاء "مشروع تم إنشاؤه".

يمكنك بعد ذلك <LocalizedLink href="/guides/features/projects/editing">تعديل المشروع</LocalizedLink> تشغيل `tuist تحرير` ، وسيقوم Xcode بفتح مشروع حيث يمكنك تحرير المشروع. أحد الملفات التي يتم إنشاؤها هو `Project.swift` ، والذي يحتوي على تعريف مشروعك. إذا كنت معتادًا على مدير حزم سويفت، ففكر في الأمر على أنه `Package.swift` ولكن مع لغة مشاريع Xcode.

:::: code-group
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

::::

::: info
لقد تعمدنا إبقاء قائمة القوالب المتاحة قصيرة لتقليل نفقات الصيانة. إذا كنت ترغب
في إنشاء مشروع لا يمثل تطبيقًا، على سبيل المثال إطار عمل، يمكنك استخدام `tuist
init` كنقطة بداية ثم تعديل المشروع الذي تم إنشاؤه ليناسب احتياجاتك.
:::

## إنشاء مشروع يدوياً {#manually-creating-a-project}

بدلاً من ذلك، يمكنك إنشاء المشروع يدوياً. نوصي بالقيام بذلك فقط إذا كنت معتادًا
بالفعل على تويست ومفاهيمه. أول شيء ستحتاج إلى القيام به هو إنشاء دلائل إضافية
لهيكل المشروع:

```bash
mkdir MyFramework
cd MyFramework
```

ثم قم بإنشاء ملف `Tuist.swift.swift` ، والذي سيقوم بتهيئة ملف تويست ويستخدمه
تويست لتحديد الدليل الجذر للمشروع، وملف `Project.swift` ، حيث سيتم الإعلان عن
مشروعك:

:::: code-group
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

::::

::: warning
يستخدم تويست الدليل `تويست/` لتحديد جذر مشروعك، ومن هناك يبحث عن ملفات البيان
الأخرى التي تملأ الدلائل. نوصي بإنشاء تلك الملفات باستخدام المحرر الذي تختاره،
ومن تلك النقطة يمكنك استخدام `tuist edit` لتحرير المشروع باستخدام Xcode.
:::
