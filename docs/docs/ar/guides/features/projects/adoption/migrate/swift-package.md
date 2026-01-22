---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# ترحيل حزمة Swift {#migrate-a-swift-package}

ظهر Swift Package Manager كمدير تبعيات لرمز Swift الذي وجد نفسه بشكل غير مقصود
يحل مشكلة إدارة المشاريع ودعم لغات البرمجة الأخرى مثل Objective-C. نظرًا لأن
الأداة تم تصميمها لغرض مختلف، فقد يكون من الصعب استخدامها لإدارة المشاريع على
نطاق واسع لأنها تفتقر إلى المرونة والأداء والقوة التي يوفرها Tuist. وقد تم توضيح
ذلك جيدًا في مقال [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)، الذي
يتضمن الجدول التالي الذي يقارن أداء Swift Package Manager ومشاريع Xcode الأصلية:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

غالبًا ما نصادف مطورين ومنظمات يشككون في الحاجة إلى Tuist نظرًا لأن Swift
Package Manager يمكن أن يؤدي دورًا مشابهًا في إدارة المشاريع. يغامر البعض
بالانتقال إلى الإصدار الأحدث ليكتشفوا لاحقًا أن تجربة المطورين لديهم قد تدهورت
بشكل كبير. على سبيل المثال، قد يستغرق إعادة فهرسة ملف تمت إعادة تسميته ما يصل
إلى 15 ثانية. 15 ثانية!

**من غير المؤكد ما إذا كانت Apple ستجعل Swift Package Manager مدير مشاريع مصممًا
للتوسع.** ومع ذلك، لا نرى أي مؤشرات على حدوث ذلك. في الواقع، نرى العكس تمامًا.
فهم يتخذون قرارات مستوحاة من Xcode، مثل تحقيق الراحة من خلال التكوينات الضمنية،
والتي <LocalizedLink href="/guides/features/projects/cost-of-convenience">كما
تعلمون،</LocalizedLink> هي مصدر التعقيدات على نطاق واسع. نعتقد أن Apple ستحتاج
إلى العودة إلى المبادئ الأساسية وإعادة النظر في بعض القرارات التي كانت منطقية
كمدير تبعيات ولكنها ليست كذلك كمدير مشاريع، على سبيل المثال استخدام لغة مجمعة
كواجهة لتعريف المشاريع.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
يعامل Tuist Swift Package Manager كمدير تبعيات، وهو مدير رائع. نستخدمه لحل
التبعيات وبنائها. لا نستخدمه لتعريف المشاريع لأنه غير مصمم لذلك.
<!-- -->
:::

## الانتقال من Swift Package Manager إلى Tuist {#migrating-from-swift-package-manager-to-tuist}

تجعل أوجه التشابه بين Swift Package Manager و Tuist عملية الترحيل سهلة. الفرق
الرئيسي هو أنك ستقوم بتعريف مشاريعك باستخدام DSL الخاص بـ Tuist بدلاً من
`Package.swift`.

أولاً، قم بإنشاء ملف `Project.swift` بجوار ملف `Package.swift`. سيحتوي ملف
`Project.swift` على تعريف مشروعك. فيما يلي مثال على ملف `Project.swift` الذي
يعرّف مشروعًا بهدف واحد:

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

- **ProjectDescription**: بدلاً من استخدام `PackageDescription` ، ستستخدم
  `ProjectDescription`.
- **المشروع:** بدلاً من تصدير حزمة `مثيل` ، ستقوم بتصدير مشروع `مثيل`.
- **لغة Xcode:** العناصر الأولية التي تستخدمها لتعريف مشروعك تحاكي لغة Xcode،
  لذا ستجد مخططات وأهداف ومراحل بناء وغيرها.

ثم قم بإنشاء ملف `Tuist.swift` بالمحتوى التالي:

```swift
import ProjectDescription

let tuist = Tuist()
```

`يحتوي ملف Tuist.swift` على تكوين مشروعك ويُستخدم مساره كمرجع لتحديد جذر مشروعك.
يمكنك الاطلاع على وثيقة
<LocalizedLink href="/guides/features/projects/directory-structure">هيكل
الدليل</LocalizedLink> لمعرفة المزيد عن هيكل مشاريع Tuist.

## تحرير المشروع {#edit-the-project}

يمكنك استخدام <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> لتحرير المشروع في Xcode. سيقوم الأمر بإنشاء مشروع Xcode
يمكنك فتحه والبدء في العمل عليه.

```bash
tuist edit
```

اعتمادًا على حجم المشروع، يمكنك استخدامه دفعة واحدة أو بشكل تدريجي. نوصي بالبدء
بمشروع صغير للتعرف على DSL وسير العمل. نصيحتنا هي أن تبدأ دائمًا من الهدف الأكثر
اعتمادًا عليه وتواصل العمل حتى تصل إلى الهدف الأعلى مستوى.
