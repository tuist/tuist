---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# القوالب {#templates}

في المشاريع ذات البنية الثابتة، قد يرغب المطورون في إنشاء مكونات أو ميزات جديدة
تتوافق مع المشروع. باستخدام `tuist scaffold` يمكنك إنشاء ملفات من قالب. يمكنك
تعريف قوالبك الخاصة أو استخدام القوالب المرفقة مع Tuist. فيما يلي بعض
السيناريوهات التي قد يكون فيها الهيكل المفيد:

- أنشئ ميزة جديدة تتبع بنية معينة: `tuist scaffold viper --name MyFeature`.
- إنشاء مشاريع جديدة: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist لا تتدخل في محتوى القوالب الخاصة بك أو الغرض من استخدامها. كل ما عليك هو
وضعها في دليل محدد.
<!-- -->
:::

## تعريف القالب {#defining-a-template}

لتعريف القوالب، يمكنك تشغيل
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> ثم إنشاء دليل باسم `name_of_template` تحت
`Tuist/Templates` الذي يمثل القالب الخاص بك. تحتاج القوالب إلى ملف بيان،
`name_of_template.swift` يصف القالب. لذا، إذا كنت تنشئ قالبًا باسم `framework` ،
فيجب عليك إنشاء دليل جديد `framework` في `Tuist/Templates` مع ملف بيان باسم
`framework.swift` قد يبدو كما يلي:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## استخدام قالب {#using-a-template}

بعد تحديد القالب، يمكننا استخدامه من خلال الأمر `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

:::: المعلومات
<!-- -->
نظرًا لأن النظام الأساسي هو حجة اختيارية، يمكننا أيضًا استدعاء الأمر بدون حجة
`--platform macos`.
<!-- -->
:::

إذا لم توفر `.string` و `.files` مرونة كافية، يمكنك الاستفادة من لغة القوالب
[Stencil](https://stencil.fuller.li/en/latest/) عبر `.file`. بالإضافة إلى ذلك،
يمكنك أيضًا استخدام المرشحات الإضافية المحددة هنا.

باستخدام التقدير المتعدد، فإن `\(nameAttribute)` أعلاه سيتم تحويله إلى `{{ name
}}`. إذا كنت ترغب في استخدام مرشحات Stencil في تعريف القالب، فيمكنك استخدام هذا
التقدير يدويًا وإضافة أي مرشحات تريدها. على سبيل المثال، يمكنك استخدام `{ { name
| lowercase } }` بدلاً من `\(nameAttribute)` للحصول على القيمة الصغيرة لخاصية
الاسم.

يمكنك أيضًا استخدام `.directory` الذي يتيح إمكانية نسخ مجلدات كاملة إلى مسار
معين.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
تدعم القوالب استخدام
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink> لإعادة استخدام الكود عبر القوالب.
<!-- -->
:::
