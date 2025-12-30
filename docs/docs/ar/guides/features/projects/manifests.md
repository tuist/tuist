---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# المظاهر {#manifests}

يستخدم تويست افتراضيًا ملفات سويفت كطريقة أساسية لتحديد المشاريع ومساحات العمل
وتهيئة عملية الإنشاء. يُشار إلى هذه الملفات باسم ملفات البيان **** في جميع أنحاء
الوثائق.

كان قرار استخدام Swift مستوحى من [Swift Package Manager]
(https://www.swift.org/documentation/package-manager/)، والذي يستخدم أيضًا ملفات
Swift لتحديد الحزم. وبفضل استخدام Swift، يمكننا الاستفادة من المحول البرمجي
للتحقق من صحة المحتوى وإعادة استخدام الشيفرة عبر ملفات البيان المختلفة، و Xcode
لتوفير تجربة تحرير من الدرجة الأولى بفضل تسليط الضوء على بناء الجملة والإكمال
التلقائي والتحقق من الصحة.

::: info CACHING
<!-- -->
نظرًا لأن ملفات البيان هي ملفات Swift التي تحتاج إلى تجميعها، فإن Tuist يخزن
نتائج التجميع مؤقتًا لتسريع عملية التحليل. لذلك، ستلاحظ أنه في المرة الأولى التي
تقوم فيها بتشغيل تويست، قد يستغرق إنشاء المشروع وقتًا أطول قليلاً. ستكون عمليات
التشغيل اللاحقة أسرع.
<!-- -->
:::

## مشروع.سويفت {#projectswift}

يُعلن البيان
<LocalizedLink href="/references/project-description/structs/project">`Project.swift.swift`</LocalizedLink>
عن مشروع Xcode. يتم إنشاء المشروع في نفس الدليل الذي يوجد فيه ملف البيان بالاسم
المشار إليه في خاصية `الاسم`.

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
المتغير الوحيد الذي يجب أن يكون في جذر البيان هو `دع المشروع = المشروع(...)`.
إذا كنت بحاجة إلى إعادة استخدام الشيفرة عبر أجزاء مختلفة من البيان، يمكنك
استخدام دوال سويفت.
<!-- -->
:::

## مساحة العمل.سويفت {#workspaceswift}

بشكل افتراضي، يُنشئ تويست [مساحة عمل Xcode]
(https://developer.apple.com/documentation/xcode/projects-and-workspaces) تحتوي
على المشروع الذي يتم إنشاؤه ومشاريع تبعياته. إذا كنت ترغب لأي سبب من الأسباب في
تخصيص مساحة العمل لإضافة مشاريع إضافية أو تضمين ملفات ومجموعات إضافية، يمكنك
القيام بذلك عن طريق تحديد بيان
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift.swift`</LocalizedLink>.

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
سيقوم تويست بحل الرسم البياني للتبعية وتضمين مشاريع التبعيات في مساحة العمل. لا
تحتاج إلى تضمينها يدويًا. هذا ضروري لنظام البناء لحل التبعيات بشكل صحيح.
<!-- -->
:::

### مشروع متعدد أو أحادي {#multi-or-monoproject}

السؤال الذي غالباً ما يطرح نفسه هو ما إذا كان يجب استخدام مشروع واحد أو عدة
مشاريع في مساحة العمل. في عالم بدون تويست حيث قد يؤدي إعداد مشروع واحد إلى
تعارضات متكررة في Git، يتم تشجيع استخدام مساحات العمل. ومع ذلك، نظرًا لأننا لا
نوصي بتضمين مشاريع Xcode التي تم إنشاؤها بواسطة تويست في مستودع Git، فإن تعارضات
Git ليست مشكلة. ولذلك، فإن قرار استخدام مشروع واحد أو عدة مشاريع في مساحة عمل
يعود إليك.

في مشروع تويست نعتمد في مشروع تويست على المشاريع الأحادية لأن وقت التوليد البارد
أسرع (عدد أقل من ملفات البيان للتحويل البرمجي) ونستفيد من
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink> كوحدة تغليف. ومع ذلك، قد ترغب في استخدام مشاريع Xcode
كوحدة تغليف لتمثيل مجالات مختلفة من تطبيقك، وهو ما يتوافق بشكل أكبر مع بنية
مشروع Xcode الموصى به.

## تويست.سويفت {#tuistswift}

يوفّر تويست
<LocalizedLink href="/contributors/principles.html#default-to-conventions">
إعدادات افتراضية </LocalizedLink> لتبسيط تكوين المشروع. ومع ذلك، يمكنك تخصيص
التهيئة عن طريق تحديد
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
في جذر المشروع، والذي يستخدمه Tuist لتحديد جذر المشروع.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
