---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# المكونات الإضافية {#plugins}

المكوّنات الإضافية هي أداة لمشاركة وإعادة استخدام القطع الأثرية ل Tuist عبر
مشاريع متعددة. يتم دعم القطع الأثرية التالية:

- <LocalizedLink href="/guides/features/projects/code-sharing">مساعدي وصف المشروع</LocalizedLink> عبر مشاريع متعددة.
- <LocalizedLink href="/guides/features/projects/templates">القوالب</LocalizedLink> عبر مشاريع متعددة.
- المهام عبر مشاريع متعددة.
- <LocalizedLink href="/guides/features/projects/synthesized-files">قالب ملحق الموارد</LocalizedLink> عبر مشاريع متعددة

لاحظ أن الإضافات مصممة لتكون طريقة بسيطة لتوسيع وظائف تويست. لذلك هناك **بعض
القيود التي يجب مراعاتها**:

- لا يمكن أن تعتمد الإضافة على إضافة أخرى.
- لا يمكن أن يعتمد المكون الإضافي على حزم Swift التابعة لجهة خارجية
- لا يمكن للمكون الإضافي استخدام مساعدي وصف المشروع من المشروع الذي يستخدم
  المكون الإضافي.

إذا كنت بحاجة إلى مزيد من المرونة، ففكر في اقتراح ميزة للأداة أو بناء الحل الخاص
بك على إطار توليد تويست،
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## أنواع المكونات الإضافية {#plugin-types}

### البرنامج المساعد المساعد لوصف المشروع {#project-description-helper-plugin}

يتم تمثيل المكوّن الإضافي المساعد لوصف المشروع بدليل يحتوي على `Plugin.swift`
ملف بيان يوضح اسم المكوّن الإضافي ودليل `ProjectDescriptionHelpers` يحتوي على
ملفات Swift المساعدة.

:::: code-group
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
::::

### المكون الإضافي لقوالب ملحقات الموارد {#resource-accessor-templates-plugin}

إذا كنت بحاجة إلى مشاركة <LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">ملحقات الموارد</LocalizedLink> المركّبة يمكنك استخدام هذا النوع من المكوّنات الإضافية. يُمثّل المكوّن الإضافي بدليل يحتوي على `Plugin.swift` ملف بيان يُعلن
اسم المكوّن الإضافي ودليل `ResourceSynthesizizizers` يحتوي على ملفات قالب قالب
ملحق الموارد.


:::: code-group
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
::::

اسم القالب هو إصدار [حالة الجمل] (https://en.wikipedia.org/wiki/Camel_case) من
نوع المورد:

| نوع المورد        | اسم ملف القالب                   |
| ----------------- | -------------------------------- |
| الأوتار           | سلاسل.استنسل                     |
| الأصول            | الأصول.استنسل                    |
| قوائم العقارات    | القوائم.استنسل                   |
| الخطوط            | الخطوط.استنسل                    |
| البيانات الأساسية | CoreData.stencil.stencil         |
| منشئ الواجهة      | InterfaceBuilder.stencil.stencil |
| JSON              | JSON.stencil                     |
| YAML              | YAML.stencil.stencil             |

عند تحديد مركبات الموارد في المشروع، يمكنك تحديد اسم المكون الإضافي لاستخدام
القوالب من المكون الإضافي:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### المكون الإضافي للمهمة <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
تم إهمال المكونات الإضافية للمهام. راجع [هذه التدوينة]
(https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) إذا كنت تبحث عن
حل أتمتة لمشروعك.
<!-- -->
:::

المهام هي `$ PATH`-المسار -المسارات التنفيذية المكشوفة التي يمكن استدعاؤها من
خلال الأمر `tuist` إذا كانت تتبع اصطلاح التسمية `tuist-<task-name>`. في الإصدارات السابقة، وفرت تويست بعض الاصطلاحات والأدوات الضعيفة تحت `tuist plugin` إلى `بناء` و `تشغيل` و `اختبار` و `أرشفة` المهام التي تمثلها الملفات التنفيذية في حزم سويفت، لكننا أهملنا هذه الميزة لأنها تزيد من عبء الصيانة وتعقيد الأداة.

إذا كنت تستخدم تويست لتوزيع المهام، فإننا نوصي ببناء
- يمكنك الاستمرار في استخدام `ProjectAutomation.xcframework` الموزعة مع كل إصدار
  من إصدارات Tuist للوصول إلى الرسم البياني للمشروع من منطقك باستخدام `دع الرسم
  البياني = حاول Tuist.graph()`. يستخدم الأمر عملية النظام لتشغيل الأمر `tuist`
  وإرجاع التمثيل داخل الذاكرة للرسم البياني للمشروع.
- لتوزيع المهام، نوصي بتضمين ثنائي سمين يدعم `arm64` و `x86_64` في إصدارات
  GitHub، واستخدام [Mise] (https://mise.jdx.dev) كأداة تثبيت. لتوجيه Mise حول
  كيفية تثبيت أداتك، ستحتاج إلى مستودع إضافي. يمكنك استخدام [تويست]
  (https://github.com/asdf-community/asdf-tuist) كمرجع.
- إذا قمت بتسمية أداتك `tuist-{xxx}` ويمكن للمستخدمين تثبيتها عن طريق تشغيل
  `mise install` ، يمكنهم تشغيلها إما باستدعائها مباشرة، أو من خلال `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
نحن نخطط لدمج نماذج `ProjectAutomation` و `XcodeGraph` في إطار عمل واحد متوافق
مع الإصدارات السابقة يعرض جوهر الرسم البياني للمشروع للمستخدم. علاوة على ذلك،
سنقوم باستخراج منطق التوليد في طبقة جديدة، `XcodeGraph` التي يمكنك استخدامها
أيضًا من CLI الخاص بك. فكر في الأمر على أنه بناء تويست الخاص بك.
<!-- -->
:::

## استخدام المكونات الإضافية {#using-plugins}

لاستخدام مكون إضافي، يجب عليك إضافته إلى ملف
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift.swift`</LocalizedLink>
ملف البيان الخاص بمشروعك:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

إذا كنت ترغب في إعادة استخدام مكون إضافي عبر المشاريع التي تعيش في مستودعات
مختلفة، يمكنك دفع المكون الإضافي الخاص بك إلى مستودع Git والإشارة إليه في ملف
`Tuist.swift.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

بعد إضافة الإضافات، سيقوم `tuist install` بجلب الإضافات في دليل ذاكرة التخزين
المؤقت العامة.

::: info NO VERSION RESOLUTION
<!-- -->
كما لاحظت، نحن لا نوفر دقة الإصدار للإضافات. نوصي باستخدام علامات Git أو SHAs
لضمان إمكانية التكرار.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
عند استخدام المكون الإضافي لمساعدي وصف المشروع، يكون اسم الوحدة النمطية التي
تحتوي على المساعدين هو اسم المكون الإضافي
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
