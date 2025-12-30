---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# ابدأ {#get-started}

أسهل طريقة لبدء استخدام Tuist في أي دليل أو في دليل مشروع Xcode أو مساحة العمل
الخاصة بك:

:::: مجموعة الرموز

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

سيرشدك الأمر خلال الخطوات اللازمة
<LocalizedLink href="/guides/features/projects"> لإنشاء مشروع تم
إنشاؤه</LocalizedLink> أو دمج مشروع Xcode أو مساحة عمل موجودة. يساعدك على توصيل
الإعداد الخاص بك بالخادم البعيد، مما يتيح لك الوصول إلى ميزات مثل
<LocalizedLink href="/guides/features/selective-testing"> الاختبار
الانتقائي</LocalizedLink>، <LocalizedLink href="/guides/features/previews">
والمراجعات</LocalizedLink>، و <LocalizedLink href="/guides/features/registry">
السجل</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
إذا كنت ترغب في ترحيل مشروع قائم إلى المشاريع التي تم إنشاؤها لتحسين تجربة
المطور والاستفادة من <LocalizedLink href="/guides/features/cache">ذاكرة التخزين
المؤقت</LocalizedLink>، راجع دليل
الترحيل<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project"></LocalizedLink>.
<!-- -->
:::
