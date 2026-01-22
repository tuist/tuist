---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# رؤى الحزمة {#bundle-size}

:::: متطلبات التحذير
<!-- -->
- أ <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع تويست
  <LocalizedLink href="/guides/server/accounts-and-projects">تويست</LocalizedLink>
<!-- -->
:::

كلما أضفت المزيد من الميزات إلى تطبيقك، يزداد حجم حزمة تطبيقك باستمرار. في حين
أن بعض النمو في حجم الحزمة أمر لا مفر منه مع شحن المزيد من التعليمات البرمجية
والأصول، إلا أن هناك العديد من الطرق لتقليل هذا النمو، مثل ضمان عدم تكرار أصولك
عبر حزمك أو تجريد الرموز الثنائية غير المستخدمة. يوفر لك Tuist الأدوات والرؤى
لمساعدتك في الحفاظ على صغر حجم تطبيقك - كما أننا نراقب حجم تطبيقك بمرور الوقت.

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

يحلل الأمر `tuist inspect bundle` الحزمة ويزودك برابط لرؤية نظرة عامة مفصلة عن
الحزمة بما في ذلك فحص محتويات الحزمة أو تحليل الوحدة النمطية:

![الحزمة المحللة] (/images/guides/features/bundle-size/analyzed-bundle.png)

## التكامل المستمر {#continuous-integration}

لتتبع حجم الحزمة بمرور الوقت، ستحتاج إلى تحليل الحزمة على CI. أولاً، ستحتاج إلى
التأكد من أن CI الخاص بك هو
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">
مصادق عليه </LocalizedLink>:

مثال على سير العمل لإجراءات GitHub يمكن أن يبدو بعد ذلك على النحو التالي:

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

![الرسم البياني لحجم الحزمة]
(/images/guides/features/bundle-size/bundle-size-graph.png)

## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

:::: تحذير التكامل مع منصة GIT مطلوب
<!-- -->
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج مشروعك
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
مع <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>منصة
<LocalizedLink href="/guides/server/authentication">Git.
<!-- -->
:::

بمجرد توصيل مشروع Tuist الخاص بك مع منصة Git الخاصة بك مثل
[GitHub](https://github.com)، سيقوم Tuist بنشر تعليق مباشرة في طلبات السحب/الدمج
الخاصة بك كلما قمت بتشغيل `tuist تفقد الحزمة`: ![تعليق تطبيق GitHub مع الحزم
التي تم فحصها](/images/guides/features/bundle-size/github-app-with-bundles.png)
