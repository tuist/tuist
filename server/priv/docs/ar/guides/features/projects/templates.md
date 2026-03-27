---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# القوالب {#templates}

في المشاريع ذات البنية الراسخة، قد يرغب المطورون في تمهيد مكونات أو ميزات جديدة
تتسق مع المشروع. مع `سقالة تويست` يمكنك إنشاء ملفات من قالب. يمكنك تحديد القوالب
الخاصة بك أو استخدام القوالب التي يتم بيعها مع Tuist. هذه بعض السيناريوهات التي
قد تكون فيها السقالات مفيدة:

- قم بإنشاء ميزة جديدة تتبع بنية معينة: `tuist سقالة الأفعى - الاسم MyFeature`.
- إنشاء مشاريع جديدة: `تويست سقالة ميزة المشروع - اسم المشروع الرئيسي`

::: info NON-OPINIONATED
<!-- -->
تويست ليس له رأي في محتوى القوالب الخاصة بك، وما تستخدمها من أجله. فهي مطلوبة
فقط لتكون في دليل محدد.
<!-- -->
:::

## تعريف القالب {#defining-a-template}

ولتعريف القوالب، يمكنك تشغيل <LocalizedLink href="/guides/features/projects/editing">`tuist تحرير`</LocalizedLink> ثم إنشاء دليل يسمى `name_of_of_template` ضمن `Tuist/Templates` الذي يمثل القالب الخاص بك. تحتاج القوالب إلى ملف بيان، `name_of_of_template.swift.` الذي يصف القالب. لذلك إذا كنت تقوم بإنشاء قالب يسمى `إطار العمل` ، يجب عليك إنشاء دليل جديد `إطار العمل` في `Tuist/Templates` مع ملف بيان يسمى `framework.swift` والذي يمكن أن يبدو هكذا:


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

بعد تحديد القالب، يمكننا استخدامه من الأمر `سقالة`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
نظرًا لأن النظام الأساسي هو وسيطة اختيارية، يمكننا أيضًا استدعاء الأمر بدون الوسيطة `-- النظام الأساسي macos`.
:::

إذا لم يوفر لك `.string` و `.files` مرونة كافية، يمكنك الاستفادة من لغة النمذجة
[Stencil] (https://stencil.fuller.li/en/latest/) عبر حالة `.file`. بالإضافة إلى
ذلك، يمكنك أيضًا استخدام مرشحات إضافية محددة هنا.

باستخدام استيفاء السلسلة، `\(nameAttribute)` أعلاه سيحل إلى `{{ name }}}`. إذا
كنت ترغب في استخدام مرشحات الاستنسل في تعريف القالب، يمكنك استخدام هذا الاستيفاء
يدويًا وإضافة أي مرشحات تريدها. على سبيل المثال، يمكنك استخدام `{ { الاسم | اسم
| أحرف صغيرة } }` بدلًا من `\(nameAttribute)` للحصول على القيمة ذات الأحرف
الصغيرة لسمة الاسم.

يمكنك أيضًا استخدام `.directory` الذي يتيح إمكانية نسخ مجلدات كاملة إلى مسار
معين.

::: tip PROJECT DESCRIPTION HELPERS
تدعم القوالب استخدام <LocalizedLink href="/guides/features/projects/code-sharing">مساعدي وصف المشروع</LocalizedLink> لإعادة استخدام الشيفرة عبر القوالب.
:::
