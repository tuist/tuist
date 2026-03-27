---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# مشاركة الرموز {#code-sharing}

أحد مضايقات Xcode عندما نستخدمه مع المشاريع الكبيرة هو أنه لا يسمح بإعادة
استخدام عناصر المشاريع بخلاف إعدادات الإنشاء من خلال `.xcconfig` الملفات. إن
القدرة على إعادة استخدام تعريفات المشروع مفيدة للأسباب التالية:

- إنه يسهل عملية الصيانة **الصيانة** لأنه يمكن تطبيق التغييرات في مكان واحد
  وتحصل جميع المشاريع على التغييرات تلقائيًا.
- يجعل من الممكن تحديد **الاتفاقيات** التي يمكن أن تتوافق معها المشاريع الجديدة.
- تكون المشاريع أكثر اتساقًا **متناسقة** وبالتالي فإن احتمالية تعطل عمليات
  الإنشاء بسبب التناقضات أقل بكثير.
- تصبح إضافة مشاريع جديدة مهمة سهلة لأنه يمكننا إعادة استخدام المنطق الحالي.

إعادة استخدام التعليمات البرمجية عبر ملفات البيان ممكنة في تويست بفضل مفهوم
مساعدي وصف المشروع **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
تحب العديد من المنظمات تويست لأنها ترى في مساعدي وصف المشروع منصة لفرق المنصة
لتقنين اصطلاحاتها الخاصة والتوصل إلى لغتها الخاصة لوصف مشاريعها. على سبيل
المثال، يتعين على مولدي المشاريع المستندة إلى YAML أن يتوصلوا إلى حل خاص بهم
قائم على YAML، أو إجبار المؤسسات على بناء أدواتهم على أساسه.
<!-- -->
:::

## مساعدو وصف المشروع {#project-description-helpers}

مساعِدات وصف المشروع هي ملفات سويفت التي يتم تجميعها في وحدة نمطية
`ProjectDescriptionHelpers` ، والتي يمكن لملفات البيان استيرادها. يتم تجميع
الوحدة النمطية عن طريق تجميع جميع الملفات الموجودة في الدليل `تويست/مساعدو وصف
المشروع`.

يمكنك استيرادها إلى ملف البيان الخاص بك عن طريق إضافة عبارة استيراد في أعلى
الملف:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`يتوفر ProjectDespeccriptionHelpers` في البيانات التالية:
- `مشروع.سويفت`
- `الحزمة.سويفت` (فقط خلف علامة المترجم `#TUIST` )
- `مساحة العمل.سويفت`

## مثال على ذلك {#example}

تحتوي المقتطفات أدناه على مثال على كيفية توسيع نموذج `Project` لإضافة منشئات
ثابتة وكيفية استخدامها من ملف `Project.swift.`:

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
لاحظ كيف أننا من خلال الدالة نحدد اصطلاحات حول اسم الأهداف، ومعرف الحزمة، وبنية
المجلدات.
<!-- -->
:::
