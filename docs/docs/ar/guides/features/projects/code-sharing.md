---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# مشاركة الكود {#code-sharing}

أحد عيوب Xcode عند استخدامه مع المشاريع الكبيرة هو أنه لا يسمح بإعادة استخدام
عناصر المشاريع بخلاف إعدادات البناء من خلال ملفات `.xcconfig`. تعد القدرة على
إعادة استخدام تعريفات المشروع مفيدة للأسباب التالية:

- يسهل ذلك صيانة **** لأن التغييرات يمكن تطبيقها في مكان واحد ويتم تطبيقها
  تلقائيًا على جميع المشاريع.
- يمكن من خلال ذلك تحديد قواعد **** يمكن للمشاريع الجديدة الالتزام بها.
- المشاريع أكثر اتساقًا **** وبالتالي تقل احتمالية حدوث أخطاء في البناء بسبب عدم
  الاتساق بشكل كبير.
- أصبح إضافة مشاريع جديدة مهمة سهلة لأننا يمكننا إعادة استخدام المنطق الحالي.

يمكن إعادة استخدام الكود عبر ملفات البيان في Tuist بفضل مفهوم مساعدات وصف
المشروع في **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
تحب العديد من المؤسسات Tuist لأنها ترى في مساعدات وصف المشروع منصة لفرق المنصة
لتقنين اصطلاحاتها الخاصة وابتكار لغتها الخاصة لوصف مشاريعها. على سبيل المثال،
يجب على مولدات المشاريع المستندة إلى YAML ابتكار حل قوالب خاص بها مستند إلى
YAML، أو إجبار المؤسسات على بناء أدواتها عليه.
<!-- -->
:::

## مساعدو وصف المشروع {#project-description-helpers}

مساعدات وصف المشروع هي ملفات Swift يتم تجميعها في وحدة نمطية،
`ProjectDescriptionHelpers` ، يمكن لملفات manifest استيرادها. يتم تجميع الوحدة
النمطية عن طريق جمع جميع الملفات الموجودة في `Tuist/ProjectDescriptionHelpers`
الدليل.

يمكنك استيرادها إلى ملف البيان الخاص بك عن طريق إضافة عبارة استيراد في أعلى
الملف:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` متاحة في البيانات التالية:
- `Project.swift`
- `Package.swift` (فقط خلف علامة التحويل البرمجي `#TUIST` )
- `Workspace.swift`

## مثال {#example}

تحتوي المقتطفات أدناه على مثال لكيفية توسيع نموذج مشروع `` لإضافة منشئات ثابتة
وكيفية استخدامها من ملف `Project.swift`:

:::: مجموعة الرموز
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
لاحظ كيف أننا نحدد من خلال الوظيفة قواعد بشأن اسم الأهداف ومعرف الحزمة وهيكل
المجلدات.
<!-- -->
:::
