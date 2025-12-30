---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# التكوين الديناميكي {#dynamic-configuration}

هناك سيناريوهات معينة قد تحتاج فيها إلى تكوين مشروعك ديناميكيًا في وقت الإنشاء.
على سبيل المثال، قد ترغب في تغيير اسم التطبيق أو معرّف الحزمة أو هدف النشر بناءً
على البيئة التي يتم فيها إنشاء المشروع. يدعم تويست ذلك عبر متغيرات البيئة، والتي
يمكن الوصول إليها من ملفات البيان.

## التهيئة من خلال متغيرات البيئة {#configuration-through-environment-variables}

يسمح تويست بتمرير التكوين من خلال متغيرات البيئة التي يمكن الوصول إليها من ملفات
البيان. على سبيل المثال:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

إذا أردت تمرير عدة متغيرات بيئة فقط افصل بينها بمسافة. على سبيل المثال:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## قراءة متغيرات البيئة من القوائم {#reading-the-environment-variables-from-manifests}

يمكن الوصول إلى المتغيرات باستخدام النوع
<LocalizedLink href="/references/project-description/enums/environment">`البيئة`</LocalizedLink>.
أي متغيرات تتبع الاصطلاح `TUIST_XXX` المحددة في البيئة أو التي يتم تمريرها إلى
تويست عند تشغيل الأوامر يمكن الوصول إليها باستخدام النوع `بيئة`. يوضح المثال
التالي كيفية الوصول إلى المتغير `TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

يؤدي الوصول إلى المتغيرات إلى إرجاع مثيل من النوع `Environment.Value?` والذي
يمكن أن يأخذ أيًا من القيم التالية:

| الحالة          | الوصف                             |
| --------------- | --------------------------------- |
| `سلسلة (سلسلة)` | يُستخدم عندما يمثل المتغير سلسلة. |

يمكنك أيضًا استرداد السلسلة أو المتغير المنطقي `البيئة` باستخدام أي من الطريقتين
المساعدتين المحددتين أدناه، وتتطلب هاتان الطريقتان تمرير قيمة افتراضية لضمان
حصول المستخدم على نتائج متسقة في كل مرة. هذا يجنبك الحاجة إلى تعريف الدالة
appName() المحددة أعلاه.

:::: مجموعة الرموز

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
