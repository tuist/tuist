---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# حزمة الأفكار {#bundle-size}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
<!-- -->
:::

مع إضافة المزيد من الميزات إلى تطبيقك، يستمر حجم حزمة التطبيق في النمو. في حين
أن بعض النمو في حجم الحزمة أمر لا مفر منه مع شحن المزيد من التعليمات البرمجية
والأصول، هناك العديد من الطرق لتقليل هذا النمو، مثل التأكد من عدم تكرار الأصول
عبر الحزم أو إزالة الرموز الثنائية غير المستخدمة. يوفر لك Tuist الأدوات
والمعلومات التي تساعدك في الحفاظ على حجم تطبيقك صغيرًا - كما أننا نراقب حجم
تطبيقك بمرور الوقت.

## الاستخدام {#استخدام}

لتحليل حزمة، يمكنك استخدام الأمر `tuist inspect bundle`:

:::: مجموعة الرموز
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

يقوم الأمر `tuist inspect bundle` بتحليل الحزمة ويوفر لك رابطًا للاطلاع على نظرة
عامة مفصلة عن الحزمة بما في ذلك مسح لمحتويات الحزمة أو تفصيل للوحدات النمطية:

![حزمة محللة](/images/guides/features/bundle-size/analyzed-bundle.png)

## التكامل المستمر {#continuous-integration}

لتتبع حجم الحزمة بمرور الوقت، ستحتاج إلى تحليل الحزمة على CI. أولاً، ستحتاج إلى
التأكد من أن CI الخاص بك
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">مصادق
عليه</LocalizedLink>:

قد يبدو مثال سير العمل لـ GitHub Actions كما يلي:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

بمجرد الإعداد، ستتمكن من رؤية كيف يتطور حجم الحزمة بمرور الوقت:

![رسم بياني لحجم
الحزمة](/images/guides/features/bundle-size/bundle-size-graph.png)

## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

:::: تحذير التكامل مع منصة GIT مطلوب
<!-- -->
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج مشروعك
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
مع <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>منصة
<LocalizedLink href="/guides/server/authentication">Git.
<!-- -->
:::

بمجرد ربط مشروع Tuist بمنصة Git الخاصة بك مثل [GitHub](https://github.com)،
سيقوم Tuist بنشر تعليق مباشرة في طلبات السحب/الدمج الخاصة بك كلما قمت بتشغيل
`tuist inspect bundle`: ![تعليق تطبيق GitHub مع الحزم التي تم
فحصها](/images/guides/features/bundle-size/github-app-with-bundles.png)
