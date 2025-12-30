---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# ترحيل حزمة سويفت {#migrate-a-swift-package}

ظهرت Swift Package Manager كمدير تبعية لأكواد Swift التي وجدت نفسها دون قصد في
حل مشكلة إدارة المشاريع ودعم لغات البرمجة الأخرى مثل Objective-C. نظرًا لأن
الأداة صُممت لغرض مختلف في الاعتبار، فقد يكون من الصعب استخدامها لإدارة المشاريع
على نطاق واسع لأنها تفتقر إلى المرونة والأداء والقوة التي يوفرها تويست. هذا ما
تم التقاطه بشكل جيد في مقالة [Scaling iOS في Bumble]
(https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)، والتي تتضمن
الجدول التالي الذي يقارن بين أداء مدير حزم سويفت ومشاريع Xcode الأصلية:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

غالبًا ما نصادف مطورين ومؤسسات تتحدى الحاجة إلى تويست بالنظر إلى أن مدير حزم
سويفت يمكن أن يقوم بدور مماثل في إدارة المشروع. يغامر البعض في عملية الترحيل
ليدركوا لاحقاً أن تجربة المطورين قد تدهورت بشكل ملحوظ. على سبيل المثال، قد
تستغرق إعادة تسمية ملف ما ما يصل إلى 15 ثانية لإعادة الفهرسة. 15 ثانية!

**من غير المؤكد ما إذا كانت آبل ستجعل من Swift Package Manager مدير حزم سويفت
مديراً مدمجاً للمشروعات.** ومع ذلك، نحن لا نرى أي علامات على حدوث ذلك. في
الواقع، نحن نرى العكس تماماً. إنهم يتخذون قرارات مستوحاة من Xcode، مثل تحقيق
الراحة من خلال التكوينات الضمنية، والتي
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> كما تعلمون،
</LocalizedLink> هي مصدر التعقيدات على نطاق واسع. نحن نعتقد أن الأمر يتطلب من
Apple العودة إلى المبادئ الأولى وإعادة النظر في بعض القرارات التي كانت منطقية
كمدير للتبعية وليس كمدير للمشروع، على سبيل المثال استخدام لغة مجمعة كواجهة
لتحديد المشاريع.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
يتعامل تويست مع مدير حزم سويفت كمدير تبعية، وهو مدير تبعية رائع. نحن نستخدمه لحل
التبعيات وبنائها. لا نستخدمه لتحديد المشاريع لأنه غير مصمم لذلك.
<!-- -->
:::

## الترحيل من Swift Package Manager إلى Tuist {#migrating-from-swift-package-manager-to-tuist}

إن أوجه التشابه بين Swift Package Manager و Tuist تجعل عملية الترحيل مباشرة.
الفرق الرئيسي هو أنك ستقوم بتعريف مشاريعك باستخدام DSL الخاص بـ Tuist بدلاً من
`Package.swift`.

أولاً، قم بإنشاء ملف `Project.swift.swift` بجانب ملف `Package.swift`. سيحتوي ملف
`Project.swift.swift` على تعريف مشروعك. فيما يلي مثال لملف `Project.swift.swift`
الذي يحدد مشروعًا بهدف واحد:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

بعض الأمور التي يجب ملاحظتها:

- **وصف المشروع**: بدلاً من استخدام `PackageDescription` ، ستستخدم
  `ProjectDescription`.
- **مشروع:** بدلاً من تصدير مثيل الحزمة `الحزمة` ، ستقوم بتصدير مثيل مشروع ``
  المشروع .
- **لغة Xcode:** البدائيات التي تستخدمها لتعريف مشروعك تحاكي لغة Xcode، لذا ستجد
  المخططات والأهداف ومراحل الإنشاء وغيرها.

ثم قم بإنشاء ملف `Tuist.swift.swift` بالمحتوى التالي:

```swift
import ProjectDescription

let tuist = Tuist()
```

يحتوي ملف `Tuist.swift.swift` على التكوين الخاص بمشروعك ويعمل مساره كمرجع لتحديد
جذر مشروعك. يمكنك الاطلاع على مستند
<LocalizedLink href="/guides/features/projects/directory-structure"> بنية
الدليل</LocalizedLink> لمعرفة المزيد عن بنية مشاريع تويست.

## تحرير المشروع {#edit-the-project}

يمكنك استخدام <LocalizedLink href="/guides/features/projects/editing">`tuist
تحرير`</LocalizedLink> لتحرير المشروع في Xcode. سينشئ الأمر مشروع Xcode يمكنك
فتحه وبدء العمل عليه.

```bash
tuist edit
```

اعتمادًا على حجم المشروع، يمكنك التفكير في استخدامه في لقطة واحدة أو بشكل
تدريجي. نوصي بالبدء بمشروع صغير للتعرف على DSL وسير العمل. وننصحك دائمًا بالبدء
من الهدف الأكثر اعتمادًا والعمل على طول الطريق حتى الوصول إلى الهدف الأعلى
مستوى.
