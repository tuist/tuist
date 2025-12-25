---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# ترحيل مشروع XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen] (https://github.com/yonaskolb/XcodeGen) هي أداة لإنشاء المشاريع
تستخدم YAML كـ [تنسيق تكوين]
(https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) لتحديد
مشاريع Xcode. اعتمدته العديد من المؤسسات **في محاولة للهروب من تعارضات Git
المتكررة التي تنشأ عند العمل مع مشاريع Xcode.** ومع ذلك، فإن تعارضات Git
المتكررة هي مجرد واحدة من المشاكل العديدة التي تواجهها المؤسسات. يُعرِّض Xcode
المطورين للكثير من التعقيدات والتكوينات الضمنية التي تجعل من الصعب الحفاظ على
المشاريع وتحسينها على نطاق واسع. يقصّر XcodeGen في ذلك عن طريق التصميم لأنه أداة
تولد مشاريع Xcode، وليس مدير مشروع. إذا كنت بحاجة إلى أداة تساعدك على ما هو أبعد
من توليد مشاريع Xcode، فقد ترغب في التفكير في Tuist.

::: tip SWIFT OVER YAML
<!-- -->
تفضل العديد من المؤسسات تويست كأداة لتوليد المشاريع أيضاً لأنها تستخدم سويفت
كتنسيق تكوين. سويفت هي لغة برمجة مألوفة لدى المطورين، وتوفر لهم الراحة في
استخدام ميزات الإكمال التلقائي والتحقق من النوع والتحقق من صحة الكتابة في Xcode.
<!-- -->
:::

فيما يلي بعض الاعتبارات والإرشادات لمساعدتك في ترحيل مشاريعك من XcodeGen إلى
Tuist.

## توليد المشاريع {#project-generation}

يوفر كل من تويست و XcodeGen الأمر `توليد` الذي يحول إعلان مشروعك إلى مشاريع
ومساحات عمل Xcode.

:::: مجموعة الرموز

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

يكمن الفرق في تجربة التحرير. مع تويست، يمكنك تشغيل الأمر `tuist edit` الذي يُنشئ
مشروع Xcode سريعًا يمكنك فتحه وبدء العمل عليه. هذا مفيد بشكل خاص عندما تريد
إجراء تغييرات سريعة على مشروعك.

## `مشروع.yaml` {#projectyaml}

يصبح ملف وصف مشروع XcodeGen `project.yaml.yaml` ملف الوصف `Project.swift`. علاوة
على ذلك، يمكنك الحصول على `Workspace.swift.swift` كطريقة لتخصيص كيفية تجميع
المشاريع في مساحات العمل. يمكنك أيضًا أن يكون لديك مشروع `Project.swift.swift`
مع أهداف تشير إلى أهداف من مشاريع أخرى. في هذه الحالات، سينشئ تويست مساحة عمل
Xcode تتضمن جميع المشاريع.

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
يتبنى كل من XcodeGen و Tuist لغة Xcode ومفاهيمه. ومع ذلك، يوفر لك تكوين Tuist
القائم على Swift راحة استخدام ميزات الإكمال التلقائي والتحقق من النوع والتحقق من
صحة Xcode.
<!-- -->
:::

## قوالب المواصفات {#spec-templates}

أحد عيوب YAML كلغة لتكوين المشروع هو أنه لا يدعم إمكانية إعادة الاستخدام عبر
ملفات YAML خارج الصندوق. هذه حاجة شائعة عند وصف المشاريع، وهو ما كان على
XcodeGen حله من خلال حل خاص بهم يسمى *"القوالب"*. مع تويست، فإن إمكانية إعادة
الاستخدام مدمجة في اللغة نفسها، سويفت، ومن خلال وحدة سويفت المسماة
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف المشروع
</LocalizedLink>، والتي تسمح بإعادة استخدام الشيفرة عبر جميع ملفات البيان الخاصة
بك.

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
