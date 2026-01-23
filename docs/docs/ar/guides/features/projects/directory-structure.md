---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# هيكل الدليل {#directory-structure}

على الرغم من أن مشاريع Tuist تُستخدم عادةً لتحل محل مشاريع Xcode، إلا أنها لا
تقتصر على هذا الاستخدام. تُستخدم مشاريع Tuist أيضًا لإنشاء أنواع أخرى من
المشاريع، مثل حزم SPM والقوالب والمكونات الإضافية والمهام. يصف هذا المستند بنية
مشاريع Tuist وكيفية تنظيمها. في الأقسام اللاحقة، سنتناول كيفية تعريف القوالب
والمكونات الإضافية والمهام.

## مشاريع تويست القياسية {#standard-tuist-projects}

مشاريع Tuist هي **النوع الأكثر شيوعًا من المشاريع التي يتم إنشاؤها بواسطة
Tuist.** وهي تُستخدم لإنشاء التطبيقات والأطر والمكتبات وغيرها. على عكس مشاريع
Xcode، يتم تعريف مشاريع Tuist في Swift، مما يجعلها أكثر مرونة وسهولة في الصيانة.
كما أن مشاريع Tuist أكثر وضوحًا، مما يجعلها أسهل في الفهم والتفكير. توضح البنية
التالية مشروع Tuist نموذجيًا يولد مشروع Xcode:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **دليل Tuist:** لهذا الدليل غرضان. أولاً، يشير إلى **حيث جذر المشروع هو**.
  وهذا يسمح بإنشاء مسارات نسبية إلى جذر المشروع، وكذلك تشغيل أوامر Tuist من أي
  دليل داخل المشروع. ثانياً، هو الحاوية للملفات التالية:
  - **ProjectDescriptionHelpers:** يحتوي هذا الدليل على كود Swift الذي يتم
    مشاركته عبر جميع ملفات البيان. يمكن لملفات البيان `import
    ProjectDescriptionHelpers` استخدام الكود المحدد في هذا الدليل. مشاركة الكود
    مفيدة لتجنب التكرار وضمان الاتساق عبر المشاريع.
  - **Package.swift:** يحتوي هذا الملف على تبعيات حزمة Swift لـ Tuist لدمجها
    باستخدام مشاريع وأهداف Xcode (مثل [CocoaPods](https://cococapods)) القابلة
    للتكوين والتحسين. تعرف على المزيد
    <LocalizedLink href="/guides/features/projects/dependencies">هنا</LocalizedLink>.

- **الدليل الجذري**: الدليل الجذري لمشروعك الذي يحتوي أيضًا على الدليل `Tuist`.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    يحتوي هذا الملف على تكوين Tuist الذي يتم مشاركته عبر جميع المشاريع ومساحات
    العمل والبيئات. على سبيل المثال، يمكن استخدامه لتعطيل الإنشاء التلقائي
    للمخططات، أو لتحديد هدف نشر المشاريع.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    يمثل هذا الملف مساحة عمل Xcode. يُستخدم لتجميع مشاريع أخرى ويمكنه أيضًا
    إضافة ملفات ومخططات إضافية.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    يمثل هذا الملف مشروع Xcode. ويُستخدم لتحديد الأهداف التي تشكل جزءًا من
    المشروع وتبعياتها.

عند التفاعل مع المشروع أعلاه، تتوقع الأوامر العثور على ملف `Workspace.swift` أو
ملف `Project.swift` في دليل العمل أو الدليل المشار إليه عبر علامة `--path`. يجب
أن يكون الملف في دليل أو دليل فرعي لدليل يحتوي على ملف `Tuist` ، والذي يمثل جذر
المشروع.

:::: إكرامية
<!-- -->
تسمح مساحات عمل Xcode بتقسيم المشاريع إلى عدة مشاريع Xcode لتقليل احتمالية حدوث
تعارضات في الدمج. إذا كان هذا هو الغرض الذي كنت تستخدم مساحات العمل من أجله، فلن
تحتاج إليها في Tuist. يقوم Tuist تلقائيًا بإنشاء مساحة عمل تحتوي على مشروع
ومشاريع التبعيات الخاصة به.
<!-- -->
:::

## حزمة سويفت <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

يدعم Tuist أيضًا مشاريع حزم SPM. إذا كنت تعمل على حزمة SPM، فلن تحتاج إلى تحديث
أي شيء. يلتقط Tuist تلقائيًا ملف Package.swift` في جذر `، وتعمل جميع ميزات Tuist
كما لو كانت ملف Project.swift` في `.

للبدء، قم بتشغيل `tuist install` و `tuist generate` في حزمة SPM الخاصة بك. يجب
أن يحتوي مشروعك الآن على جميع المخططات والملفات نفسها التي تراها في تكامل Xcode
SPM الأساسي. ومع ذلك، يمكنك الآن أيضًا تشغيل
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>
وتجميع معظم تبعيات ووحدات SPM الخاصة بك مسبقًا، مما يجعل عمليات البناء اللاحقة
سريعة للغاية.
