---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# ترحيل مشروع XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) هي أداة لتوليد المشاريع تستخدم
YAML كـ [تنسيق
تكوين](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
لتعريف مشاريع Xcode. اعتمدتها العديد من المؤسسات **في محاولة للهروب من تعارضات
Git المتكررة التي تنشأ عند العمل مع مشاريع Xcode.** ومع ذلك، فإن تعارضات Git
المتكررة ليست سوى واحدة من العديد من المشكلات التي تواجهها المؤسسات. يعرض Xcode
المطورين للعديد من التعقيدات والتكوينات الضمنية التي تجعل من الصعب صيانة
المشاريع وتحسينها على نطاق واسع. XcodeGen يقصر في هذا المجال بسبب تصميمه، لأنه
أداة تولد مشاريع Xcode، وليس مدير مشاريع. إذا كنت بحاجة إلى أداة تساعدك في ما هو
أبعد من توليد مشاريع Xcode، فقد ترغب في النظر في Tuist.

::: tip SWIFT OVER YAML
<!-- -->
تفضل العديد من المؤسسات استخدام Tuist كأداة لإنشاء المشاريع أيضًا لأنه يستخدم
Swift كتنسيق للتكوين. Swift هي لغة برمجة مألوفة للمطورين، وتوفر لهم سهولة
استخدام ميزات الإكمال التلقائي والتحقق من النوع والتحقق من الصحة في Xcode.
<!-- -->
:::

فيما يلي بعض الاعتبارات والإرشادات لمساعدتك في ترحيل مشاريعك من XcodeGen إلى
Tuist.

## إنشاء المشروع {#project-generation}

يوفر كل من Tuist و XcodeGen أمرًا لتوليد مشاريع Xcode ومساحات عمل ( `generate` )
يحول إعلان مشروعك إلى مشاريع ومساحات عمل Xcode.

:::: مجموعة الرموز

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

يكمن الاختلاف في تجربة التحرير. باستخدام Tuist، يمكنك تشغيل الأمر `tuist edit` ،
الذي ينشئ مشروع Xcode على الفور يمكنك فتحه والبدء في العمل عليه. هذا مفيد بشكل
خاص عندما تريد إجراء تغييرات سريعة على مشروعك.

## `project.yaml` {#projectyaml}

يصبح ملف وصف XcodeGen's `project.yaml` ` Project.swift`. علاوة على ذلك، يمكنك
الحصول على `Workspace.swift` كطريقة لتخصيص كيفية تجميع المشاريع في مساحات العمل.
يمكنك أيضًا الحصول على مشروع `Project.swift` مع أهداف تشير إلى أهداف من مشاريع
أخرى. في هذه الحالات، سيقوم Tuist بإنشاء مساحة عمل Xcode تتضمن جميع المشاريع.

:::: مجموعة الرموز

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

::: tip XCODE'S LANGUAGE
<!-- -->
يتبنى كل من XcodeGen و Tuist لغة ومفاهيم Xcode. ومع ذلك، يوفر لك تكوين Tuist
المستند إلى Swift سهولة استخدام ميزات الإكمال التلقائي والتحقق من النوع والتحقق
من الصحة في Xcode.
<!-- -->
:::

## قوالب المواصفات {#spec-templates}

أحد عيوب YAML كلغة لتكوين المشاريع هو أنها لا تدعم إعادة الاستخدام عبر ملفات
YAML بشكل مباشر. هذه حاجة شائعة عند وصف المشاريع، والتي كان على XcodeGen حلها
باستخدام حلها الخاص المسمى "قوالب" ** . مع Tuist، يتم تضمين قابلية إعادة
الاستخدام في اللغة نفسها، Swift، ومن خلال وحدة Swift تسمى
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink>، والتي تسمح بإعادة استخدام الكود عبر جميع ملفات البيان.

:::: مجموعة الرموز
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
