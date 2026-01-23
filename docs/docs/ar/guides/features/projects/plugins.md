---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# المكونات الإضافية {#plugins}

المكونات الإضافية هي أداة لمشاركة وإعادة استخدام عناصر Tuist عبر عدة مشاريع. يتم
دعم العناصر التالية:

- <LocalizedLink href="/guides/features/projects/code-sharing">مساعدو وصف
  المشروع</LocalizedLink> عبر مشاريع متعددة.
- <LocalizedLink href="/guides/features/projects/templates">القوالب</LocalizedLink>
  عبر عدة مشاريع.
- مهام عبر عدة مشاريع.
- <LocalizedLink href="/guides/features/projects/synthesized-files">قالب الوصول
  إلى الموارد</LocalizedLink> عبر عدة مشاريع

لاحظ أن المكونات الإضافية مصممة لتكون طريقة بسيطة لتوسيع وظائف Tuist. لذلك، هناك
بعض القيود التي يجب مراعاتها **** :

- لا يمكن أن يعتمد مكون إضافي على مكون إضافي آخر.
- لا يمكن أن يعتمد المكون الإضافي على حزم Swift التابعة لجهات خارجية
- لا يمكن للمكوّن الإضافي استخدام أدوات المساعدة في وصف المشروع من المشروع الذي
  يستخدم المكوّن الإضافي.

إذا كنت بحاجة إلى مزيد من المرونة، ففكر في اقتراح ميزة للأداة أو إنشاء حل خاص بك
على أساس إطار عمل Tuist،
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## أنواع المكونات الإضافية {#plugin-types}

### المكوّن الإضافي المساعد لوصف المشروع {#project-description-helper-plugin}

يتم تمثيل المكون الإضافي المساعد لوصف المشروع بواسطة دليل يحتوي على ملف بيان
`Plugin.swift` يعلن اسم المكون الإضافي ودليل `ProjectDescriptionHelpers` يحتوي
على ملفات Swift المساعدة.

:::: مجموعة الرموز
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### المكوّن الإضافي لقوالب الوصول إلى الموارد {#resource-accessor-templates-plugin}

إذا كنت بحاجة إلى مشاركة
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">مُتصلات
الموارد المُركبة</LocalizedLink>، فيمكنك استخدام هذا النوع من المكونات الإضافية.
يتم تمثيل المكون الإضافي بواسطة دليل يحتوي على ملف بيان `Plugin.swift` يعلن اسم
المكون الإضافي ودليل `ResourceSynthesizers` يحتوي على ملفات قوالب مُتصلات
الموارد.


:::: مجموعة الرموز
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

اسم القالب هو [camel case](https://en.wikipedia.org/wiki/Camel_case) نسخة من نوع
المورد:

| نوع المورد        | اسم ملف القالب           |
| ----------------- | ------------------------ |
| سلاسل             | Strings.stencil          |
| الأصول            | Assets.stencil           |
| قوائم الخصائص     | Plists.stencil           |
| الخطوط            | Fonts.stencil            |
| البيانات الأساسية | CoreData.stencil         |
| منشئ الواجهة      | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

عند تحديد مُركِّبات الموارد في المشروع، يمكنك تحديد اسم المكون الإضافي لاستخدام
القوالب من المكون الإضافي:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### مكوّن إضافي للمهمة <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
تم إهمال المكونات الإضافية للمهام. راجع [هذه
المدونة](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) إذا كنت
تبحث عن حل آلي لمشروعك.
<!-- -->
:::

المهام هي `$PATH`-exposed executables التي يمكن استدعاؤها من خلال `tuist`
command إذا كانت تتبع قواعد التسمية `tuist-<task-name>`. في الإصدارات السابقة،
قدم Tuist بعض القواعد والأدوات الضعيفة تحت `tuist plugin` to `build`, `run`,
`test` and `archive` tasks represented by executables in Swift Packages، ولكننا
قمنا بإلغاء هذه الميزة لأنها تزيد من عبء الصيانة وتعقيد الأداة.</task-name>

إذا كنت تستخدم Tuist لتوزيع المهام، نوصيك بإنشاء
- يمكنك الاستمرار في استخدام `ProjectAutomation.xcframework` الموزع مع كل إصدار
  من Tuist للوصول إلى مخطط المشروع من منطقك باستخدام `let graph = try
  Tuist.graph()`. يستخدم الأمر عملية النظام لتشغيل `tuist` الأمر، وإرجاع تمثيل
  مخطط المشروع في الذاكرة.
- لتوزيع المهام، نوصي بتضمين ثنائي سمين يدعم `arm64` و `x86_64` في إصدارات
  GitHub، واستخدام [Mise](https://mise.jdx.dev) كأداة تثبيت. لتوجيه Mise حول
  كيفية تثبيت أداتك، ستحتاج إلى مستودع مكونات إضافية. يمكنك استخدام
  [Tuist's](https://github.com/asdf-community/asdf-tuist) كمرجع.
- إذا قمت بتسمية أداتك `tuist-{xxx}` ويمكن للمستخدمين تثبيتها عن طريق تشغيل
  `mise install` ، فيمكنهم تشغيلها إما عن طريق استدعائها مباشرة أو من خلال
  `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
نخطط لدمج نماذج `ProjectAutomation` و `XcodeGraph` في إطار عمل واحد متوافق مع
الإصدارات السابقة يعرض كامل مخطط المشروع للمستخدم. علاوة على ذلك، سنستخرج منطق
التوليد إلى طبقة جديدة، `XcodeGraph` يمكنك استخدامها أيضًا من واجهة سطر الأوامر
الخاصة بك. اعتبرها بمثابة بناء Tuist خاص بك.
<!-- -->
:::

## استخدام المكونات الإضافية {#using-plugins}

لاستخدام المكون الإضافي، يجب إضافته إلى ملف
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
manifest الخاص بمشروعك:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

إذا كنت ترغب في إعادة استخدام مكون إضافي عبر مشاريع موجودة في مستودعات مختلفة،
يمكنك دفع المكون الإضافي إلى مستودع Git والإشارة إليه في ملف `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

بعد إضافة المكونات الإضافية، سيقوم `tuist install` بجلب المكونات الإضافية إلى
دليل ذاكرة التخزين المؤقتة العامة.

::: info NO VERSION RESOLUTION
<!-- -->
كما لاحظت، نحن لا نقدم حلولاً لإصدارات المكونات الإضافية. نوصي باستخدام علامات
Git أو SHA لضمان قابلية التكرار.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
عند استخدام مكون إضافي لمساعدة وصف المشروع، يكون اسم الوحدة النمطية التي تحتوي
على المساعدات هو اسم المكون الإضافي.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
