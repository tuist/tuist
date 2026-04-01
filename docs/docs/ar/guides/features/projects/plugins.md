---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# المكونات الإضافية {#plugins}

المكونات الإضافية هي أداة لمشاركة وإعادة استخدام عناصر Tuist عبر مشاريع متعددة.
يتم دعم العناصر التالية:

- <LocalizedLink href="/guides/features/projects/code-sharing">مساعدو وصف
  المشروع</LocalizedLink> عبر مشاريع متعددة.
- <LocalizedLink href="/guides/features/projects/templates">القوالب</LocalizedLink>
  عبر مشاريع متعددة.
- مهام عبر مشاريع متعددة.
- <LocalizedLink href="/guides/features/projects/synthesized-files">قالب
  Resource accessor</LocalizedLink> عبر مشاريع متعددة

لاحظ أن المكونات الإضافية مصممة لتكون طريقة بسيطة لتوسيع وظائف Tuist. لذلك هناك
**بعض القيود التي يجب أخذها في الاعتبار**:

- لا يمكن أن يعتمد مكون إضافي على مكون إضافي آخر.
- لا يمكن أن يعتمد المكون الإضافي على حزم Swift تابعة لجهات خارجية
- لا يمكن للمكوّن الإضافي استخدام مساعدات وصف المشروع من المشروع الذي يستخدم
  المكوّن الإضافي.

إذا كنت بحاجة إلى مزيد من المرونة، ففكر في اقتراح ميزة للأداة أو إنشاء حل خاص بك
بناءً على إطار عمل Tuist للتوليد،
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## أنواع المكونات الإضافية {#plugin-types}

### المكوّن الإضافي المساعد لوصف المشروع {#project-description-helper-plugin}

يتم تمثيل المكون الإضافي المساعد لوصف المشروع بواسطة دليل يحتوي على ملف بيان
`Plugin.swift` الذي يعلن اسم المكون الإضافي ودليل `ProjectDescriptionHelpers`
الذي يحتوي على ملفات Swift المساعدة.

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

### ملحق قوالب الوصول إلى الموارد {#resource-accessor-templates-plugin}

إذا كنت بحاجة إلى مشاركة
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">أدوات
الوصول إلى الموارد المركبة</LocalizedLink>، فيمكنك استخدام هذا النوع من المكونات
الإضافية. يتم تمثيل المكون الإضافي بواسطة دليل يحتوي على ملف `Plugin.swift` ملف
بيان يعلن اسم المكون الإضافي و `ResourceSynthesizers` دليل يحتوي على ملفات قوالب
أدوات الوصول إلى الموارد.


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

اسم القالب هو النسخة المكتوبة بأسلوب [camel
case](https://en.wikipedia.org/wiki/Camel_case) لنوع المورد:

| نوع المورد        | اسم ملف القالب           |
| ----------------- | ------------------------ |
| السلاسل           | Strings.stencil          |
| الأصول            | Assets.stencil           |
| قوائم الخصائص     | Plists.stencil           |
| الخطوط            | Fonts.stencil            |
| البيانات الأساسية | CoreData.stencil         |
| منشئ الواجهة      | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

عند تعريف مُركِّبات الموارد في المشروع، يمكنك تحديد اسم المكون الإضافي لاستخدام
القوالب من المكون الإضافي:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### مكوّن إضافي للمهمة <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
أصبحت ملحقات المهام قديمة. اطلع على [هذه
المدونة](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) إذا كنت
تبحث عن حل أتمتة لمشروعك.
<!-- -->
:::

المهام هي `$PATH`-ملفات تنفيذية مكشوفة يمكن استدعاؤها من خلال `tuist` الأمر إذا
كانت تتبع قواعد التسمية `tuist-<task-name>`. في الإصدارات السابقة، قدم Tuist بعض
القواعد والأدوات الضعيفة تحت `tuist plugin` لـ `build` ، `run` ، `test` و
`archive` المهام الممثلة بملفات تنفيذية في حزم Swift، لكننا قمنا بإلغاء هذه
الميزة لأنها تزيد من عبء الصيانة وتعقيد الأداة.</task-name>

إذا كنت تستخدم Tuist لتوزيع المهام، نوصيك بإنشاء
- يمكنك الاستمرار في استخدام `ProjectAutomation.xcframework` الموزع مع كل إصدار
  من Tuist للوصول إلى مخطط المشروع من منطقك باستخدام `let graph = try
  Tuist.graph()`. يستخدم الأمر عملية النظام لتشغيل الأمر `tuist` ، وإرجاع تمثيل
  مخطط المشروع في الذاكرة.
- لتوزيع المهام، نوصي بتضمين ملف ثنائي ضخم يدعم `arm64` و `x86_64` في إصدارات
  GitHub، واستخدام [Mise](https://mise.jdx.dev) كأداة تثبيت. لإرشاد Mise حول
  كيفية تثبيت أداتك، ستحتاج إلى مستودع مكونات إضافية. يمكنك استخدام
  [Tuist's](https://github.com/asdf-community/asdf-tuist) كمرجع.
- إذا قمت بتسمية أداتك `tuist-{xxx}` ويمكن للمستخدمين تثبيتها عن طريق تشغيل
  `mise install` ، فيمكنهم تشغيلها إما عن طريق استدعائها مباشرة، أو من خلال
  `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
نخطط لدمج نماذج `ProjectAutomation` و `XcodeGraph` في إطار عمل واحد متوافق مع
الإصدارات السابقة يعرض كامل مخطط المشروع للمستخدم. علاوة على ذلك، سنستخرج منطق
التوليد إلى طبقة جديدة، `XcodeGraph` التي يمكنك أيضًا استخدامها من واجهة CLI
الخاصة بك. فكر في الأمر على أنه بناء Tuist الخاص بك.
<!-- -->
:::

## استخدام المكونات الإضافية {#using-plugins}

لاستخدام المكون الإضافي، سيتعين عليك إضافته إلى ملف
<LocalizedLink href="/references/project-description/structs/tuist"> manifest
الخاص بمشروعك`Tuist.swift`</LocalizedLink>:

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

بعد إضافة المكونات الإضافية، سيقوم الأمر `tuist install` بجلب المكونات الإضافية
إلى دليل ذاكرة التخزين المؤقتة العامة.

::: info NO VERSION RESOLUTION
<!-- -->
كما لاحظت، لا نقدم تحديد إصدار للمكونات الإضافية. نوصي باستخدام علامات Git أو
SHAs لضمان قابلية التكرار.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
عند استخدام مكون إضافي لمساعدات وصف المشروع، يكون اسم الوحدة النمطية التي تحتوي
على المساعدات هو اسم المكون الإضافي
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
