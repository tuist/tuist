---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# تكامل GitHub {#github}

تُعد مستودعات Git محور الغالبية العظمى من مشاريع البرمجيات الموجودة هناك. نحن
نتكامل مع GitHub لتوفير رؤى تويست مباشرةً في طلبات السحب الخاصة بك ولتوفير بعض
التكوينات مثل مزامنة الفرع الافتراضي الخاص بك.

## الإعداد {#setup}

ستحتاج إلى تثبيت تطبيق Tuist GitHub في علامة التبويب `التكاملات` في مؤسستك:
![صورة تُظهر علامة تبويب التكاملات]
(/images/guides/integrations/gitforge/github/integrations.png)

بعد ذلك، يمكنك إضافة اتصال مشروع بين مستودع GitHub الخاص بك ومشروع Tuist الخاص
بك:

![صورة تُظهر إضافة اتصال المشروع]
(/images/guides/integrations/gitforge/github/add-project-connection.png)

## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

يقوم تطبيق GitHub بنشر تقرير تشغيل تويست، والذي يتضمن ملخصًا للعلاقات العامة،
بما في ذلك روابط لأحدث
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">
المراجعات</LocalizedLink> أو
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">
الاختبارات</LocalizedLink>:

![صورة تُظهر تعليق طلب
السحب](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
لا يتم نشر التعليق إلا عندما تكون عمليات تشغيل CI الخاصة بك
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">
مصادق عليها</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
إذا كان لديك سير عمل مخصص لا يتم تشغيله على التزام PR، ولكن على سبيل المثال،
تعليق GitHub، فقد تحتاج إلى التأكد من تعيين المتغير `GITHUB_REF` إما إلى
`refs/pull/<pr_number>/merge` أو
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

يمكنك تشغيل الأمر ذي الصلة، مثل `tuist share` ، مع متغير البيئة `GITHUB_REF`
المسبوق GITHUB_REF : <code v-pre>GITHUB_REF="refs/pull/${{{{
github.event.issue.number }}}}/head" مشاركة tuist</code>
<!-- -->
:::
