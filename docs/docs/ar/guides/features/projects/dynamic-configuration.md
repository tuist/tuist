---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# التكوين الديناميكي {#dynamic-configuration}

هناك حالات معينة قد تحتاج فيها إلى تكوين مشروعك ديناميكيًا في وقت الإنشاء. على
سبيل المثال، قد ترغب في تغيير اسم التطبيق أو معرف الحزمة أو هدف النشر بناءً على
البيئة التي يتم فيها إنشاء المشروع. يدعم Tuist ذلك عبر متغيرات البيئة، والتي
يمكن الوصول إليها من ملفات البيان.

## التكوين من خلال متغيرات البيئة {#configuration-through-environment-variables}

يسمح Tuist بتمرير التكوين عبر متغيرات البيئة التي يمكن الوصول إليها من ملفات
البيان. على سبيل المثال:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

إذا كنت تريد تمرير متغيرات بيئة متعددة، فما عليك سوى فصلها بمسافة. على سبيل
المثال:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## قراءة متغيرات البيئة من ملفات البيان {#reading-the-environment-variables-from-manifests}

يمكن الوصول إلى المتغيرات باستخدام النوع
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
أي متغيرات تتبع القاعدة `TUIST_XXX` المحددة في البيئة أو التي يتم تمريرها إلى
Tuist عند تشغيل الأوامر سيكون من الممكن الوصول إليها باستخدام النوع
`Environment`. يوضح المثال التالي كيفية الوصول إلى المتغير `TUIST_APP_NAME`:

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

| حالة الأحرف       | الوصف                             |
| ----------------- | --------------------------------- |
| `.string(String)` | يُستخدم عندما تمثل المتغير سلسلة. |

يمكنك أيضًا استرداد المتغير `Environment` الذي يمثل سلسلة أو قيمة منطقية
باستخدام أي من الطرق المساعدة المحددة أدناه، وتتطلب هذه الطرق تمرير قيمة
افتراضية لضمان حصول المستخدم على نتائج متسقة في كل مرة. وهذا يتجنب الحاجة إلى
تعريف الدالة appName() المحددة أعلاه.

:::: مجموعة الرموز

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
