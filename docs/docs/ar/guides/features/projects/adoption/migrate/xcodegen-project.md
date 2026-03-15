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
المطورين للكثير من التعقيدات والتكوينات الضمنية التي تجعل من الصعب صيانة
المشاريع وتحسينها على نطاق واسع. يخفق XcodeGen في هذا المجال بسبب تصميمه، لأنه
أداة تُنشئ مشاريع Xcode، وليس مدير مشاريع. إذا كنت بحاجة إلى أداة تساعدك في ما
هو أبعد من إنشاء مشاريع Xcode، فقد ترغب في التفكير في استخدام Tuist.

::: tip SWIFT OVER YAML
<!-- -->
تفضل العديد من المؤسسات استخدام Tuist كأداة لإنشاء المشاريع أيضًا لأنه يستخدم
Swift كتنسيق للتكوين. Swift هي لغة برمجة مألوفة للمطورين، وتوفر لهم راحة استخدام
ميزات الإكمال التلقائي والتحقق من النوع والتحقق من الصحة في Xcode.
<!-- -->
:::

فيما يلي بعض الاعتبارات والإرشادات لمساعدتك في ترحيل مشاريعك من XcodeGen إلى
Tuist.

## إنشاء المشروع {#project-generation}

يوفر كل من Tuist و XcodeGen أمر " `" لإنشاء "` " الذي يحول إعلان مشروعك إلى
مشاريع ومساحات عمل Xcode.

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
الذي ينشئ مشروع Xcode على الفور يمكنك فتحه والبدء في العمل عليه. وهذا مفيد بشكل
خاص عندما تريد إجراء تغييرات سريعة على مشروعك.

## `project.yaml` {#projectyaml}

يصبح ملف الوصف project.yaml الخاص بـ XcodeGen `` هو `Project.swift`. علاوة على
ذلك، يمكنك استخدام `Workspace.swift` كطريقة لتخصيص كيفية تجميع المشاريع في
مساحات العمل. يمكنك أيضًا إنشاء مشروع `Project.swift` يحتوي على أهداف تشير إلى
أهداف من مشاريع أخرى. في هذه الحالات، سيقوم Tuist بإنشاء مساحة عمل Xcode تتضمن
جميع المشاريع.

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
يتبنى كل من XcodeGen و Tuist لغة ومفاهيم Xcode. ومع ذلك، توفر لك التهيئة
المستندة إلى Swift في Tuist الراحة في استخدام ميزات الإكمال التلقائي والتحقق من
النوع والتحقق من الصحة في Xcode.
<!-- -->
:::

## قوالب المواصفات {#spec-templates}

أحد عيوب لغة YAML كلغة لتكوين المشاريع هو أنها لا تدعم إعادة الاستخدام عبر ملفات
YAML بشكل افتراضي. هذه حاجة شائعة عند وصف المشاريع، والتي كان على XcodeGen حلها
باستخدام حل خاص بها يسمى "قوالب" ** . مع Tuist، فإن قابلية إعادة الاستخدام مدمجة
في اللغة نفسها، Swift، ومن خلال وحدة Swift تسمى
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink>، والتي تسمح بإعادة استخدام الكود عبر جميع ملفات البيان
الخاصة بك.

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
