---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# المظاهر {#manifests}

يستخدم Tuist ملفات Swift بشكل افتراضي كطريقة أساسية لتعريف المشاريع ومساحات
العمل وتكوين عملية الإنشاء. يشار إلى هذه الملفات باسم ملفات البيان **manifest
files** في جميع أنحاء الوثائق.

جاء قرار استخدام Swift مستوحى من [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)، الذي يستخدم
أيضًا ملفات Swift لتعريف الحزم. بفضل استخدام Swift، يمكننا الاستفادة من المُجمع
للتحقق من صحة المحتوى وإعادة استخدام الكود عبر ملفات البيانات المختلفة، واستخدام
Xcode لتوفير تجربة تحرير من الدرجة الأولى بفضل تمييز الصيغة النحوية والإكمال
التلقائي والتحقق من الصحة.

::: info CACHING
<!-- -->
نظرًا لأن ملفات البيان هي ملفات Swift تحتاج إلى ترجمة، يقوم Tuist بتخزين نتائج
الترجمة مؤقتًا لتسريع عملية التحليل. لذلك، ستلاحظ أن أول مرة تقوم فيها بتشغيل
Tuist، قد يستغرق إنشاء المشروع وقتًا أطول قليلاً. ستكون عمليات التشغيل اللاحقة
أسرع.
<!-- -->
:::

## مشروع.سويفت {#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
يعلن الملف manifest عن مشروع Xcode. يتم إنشاء المشروع في نفس الدليل الذي يوجد
فيه ملف manifest بالاسم المحدد في خاصية `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
المتغير الوحيد الذي يجب أن يكون في جذر الملف هو `let project = Project(...)`.
إذا كنت بحاجة إلى إعادة استخدام الكود في أجزاء مختلفة من الملف، يمكنك استخدام
وظائف Swift.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

بشكل افتراضي، يقوم Tuist بإنشاء [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
يحتوي على المشروع الذي يتم إنشاؤه ومشاريع التبعيات الخاصة به. إذا كنت ترغب لأي
سبب من الأسباب في تخصيص مساحة العمل لإضافة مشاريع إضافية أو تضمين ملفات
ومجموعات، يمكنك القيام بذلك عن طريق تعريف
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
manifest.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

:::: المعلومات
<!-- -->
سيقوم Tuist بحل مخطط التبعية وإدراج مشاريع التبعية في مساحة العمل. لا تحتاج إلى
إدراجها يدويًا. هذا ضروري لنظام البناء لحل التبعية بشكل صحيح.
<!-- -->
:::

### مشروع متعدد أو أحادي {#multi-or-monoproject}

من الأسئلة التي تطرأ كثيرًا ما إذا كان يجب استخدام مشروع واحد أو عدة مشاريع في
مساحة العمل. في عالم بدون Tuist، حيث يؤدي إعداد مشروع واحد إلى تضارب Git متكرر،
يُنصح باستخدام مساحات العمل. ومع ذلك، نظرًا لأننا لا نوصي بتضمين مشاريع Xcode
التي تم إنشاؤها بواسطة Tuist في مستودع Git، فإن تضارب Git لا يمثل مشكلة. لذلك،
فإن قرار استخدام مشروع واحد أو عدة مشاريع في مساحة العمل متروك لك.

في مشروع Tuist، نعتمد على المشاريع الأحادية لأن وقت التوليد البارد أسرع (عدد أقل
من ملفات البيانات المطلوب تجميعها) ونستفيد من
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink> كوحدة تغليف. ومع ذلك، قد ترغب في استخدام مشاريع Xcode
كوحدة تغليف لتمثيل مجالات مختلفة من تطبيقك، وهو ما يتوافق بشكل أكبر مع بنية
المشروع الموصى بها من Xcode.

## تويست.سويفت {#tuistswift}

يوفر Tuist
<LocalizedLink href="/contributors/principles.html#default-to-conventions">إعدادات
افتراضية معقولة</LocalizedLink> لتبسيط تكوين المشروع. ومع ذلك، يمكنك تخصيص
التكوين عن طريق تعريف
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
في جذر المشروع، والذي يستخدمه Tuist لتحديد جذر المشروع.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
