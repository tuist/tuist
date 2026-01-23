---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# التحرير {#editing}

على عكس مشاريع Xcode التقليدية أو حزم Swift، حيث يتم إجراء التغييرات من خلال
واجهة مستخدم Xcode، يتم تعريف المشاريع التي تديرها Tuist في كود Swift الموجود في
ملفات البيان **manifest files**. إذا كنت على دراية بحزم Swift وملف
`Package.swift` ، فإن الطريقة متشابهة جدًا.

يمكنك تحرير هذه الملفات باستخدام أي محرر نصوص، ولكننا نوصي باستخدام سير العمل
المقدم من Tuist لهذا الغرض، `tuist edit`. ينشئ سير العمل مشروع Xcode يحتوي على
جميع ملفات البيانات ويتيح لك تحريرها وتجميعها. بفضل استخدام Xcode، تحصل على جميع
مزايا **إكمال الكود، وتمييز بناء الجملة، والتحقق من الأخطاء**.

## تحرير المشروع {#edit-the-project}

لتحرير مشروعك، يمكنك تشغيل الأمر التالي في دليل مشروع Tuist أو دليل فرعي:

```bash
tuist edit
```

ينشئ الأمر مشروع Xcode في دليل عام ويفتحه في Xcode. يتضمن المشروع دليل
`Manifests` الذي يمكنك إنشاؤه للتأكد من صحة جميع البيانات.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` يحل المشكلات التي يجب تضمينها باستخدام glob `**/{Manifest}.swift`
من الدليل الجذر للمشروع (الذي يحتوي على ملف `Tuist.swift` ). تأكد من وجود ملف
صالح `Tuist.swift` في الدليل الجذر للمشروع.
<!-- -->
:::

### تجاهل ملفات البيان {#ignoring-manifest-files}

إذا كان مشروعك يحتوي على ملفات Swift تحمل نفس اسم ملفات البيان (على سبيل المثال،
`Project.swift`) في دلائل فرعية ليست بيانات Tuist فعلية، يمكنك إنشاء ملف
`.tuistignore` في جذر مشروعك لاستبعادها من مشروع التحرير.

يستخدم ملف `.tuistignore` أنماط glob لتحديد الملفات التي يجب تجاهلها:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

هذا مفيد بشكل خاص عندما يكون لديك تجهيزات اختبار أو أمثلة كود تستخدم نفس قواعد
التسمية المستخدمة في ملفات Tuist manifest.

## تحرير وإنشاء سير العمل {#edit-and-generate-workflow}

كما لاحظت، لا يمكن إجراء التعديل من مشروع Xcode الذي تم إنشاؤه. هذا حسب التصميم
لمنع المشروع الذي تم إنشاؤه من الاعتماد على Tuist، مما يضمن لك إمكانية الانتقال
من Tuist في المستقبل دون عناء.

عند تكرار مشروع، نوصي بتشغيل `tuist edit` من جلسة طرفية للحصول على مشروع Xcode
لتحرير المشروع، واستخدام جلسة طرفية أخرى لتشغيل `tuist generate`.
