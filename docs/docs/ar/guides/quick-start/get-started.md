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

سيوجهك الأمر خلال الخطوات اللازمة لـ
<LocalizedLink href="/guides/features/projects">إنشاء مشروع تم
إنشاؤه</LocalizedLink> أو دمج مشروع أو مساحة عمل Xcode موجودة. يساعدك هذا الأمر
على توصيل إعداداتك بالخادم البعيد، مما يتيح لك الوصول إلى ميزات مثل
<LocalizedLink href="/guides/features/selective-testing">الاختبار
الانتقائي</LocalizedLink>
و<LocalizedLink href="/guides/features/previews">المعاينات</LocalizedLink>
و<LocalizedLink href="/guides/features/registry">السجل</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
إذا كنت ترغب في ترحيل مشروع موجود إلى مشاريع تم إنشاؤها لتحسين تجربة المطور
والاستفادة من <LocalizedLink href="/guides/features/cache">ذاكرة التخزين
المؤقتة</LocalizedLink>، فراجع
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">دليل
الترحيل</LocalizedLink>.
<!-- -->
:::
