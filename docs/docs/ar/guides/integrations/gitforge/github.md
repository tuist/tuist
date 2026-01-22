---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# تكامل GitHub {#github}

تعد مستودعات Git محور الغالبية العظمى من مشاريع البرامج الموجودة. نحن ندمج مع
GitHub لتوفير رؤى Tuist مباشرة في طلبات السحب الخاصة بك ولتوفير بعض الإعدادات
مثل مزامنة الفرع الافتراضي الخاص بك.

## الإعداد {#setup}

ستحتاج إلى تثبيت تطبيق Tuist GitHub في علامة التبويب "تكاملات"` في " `" في
مؤسستك: ![صورة تظهر علامة التبويب
"تكاملات"](/images/guides/integrations/gitforge/github/integrations.png)

بعد ذلك، يمكنك إضافة اتصال مشروع بين مستودع GitHub ومشروع Tuist الخاص بك:

![صورة توضح إضافة اتصال
المشروع](/images/guides/integrations/gitforge/github/add-project-connection.png)

## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

ينشر تطبيق GitHub تقرير تشغيل Tuist، والذي يتضمن ملخصًا لـ PR، بما في ذلك روابط
لأحدث
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">معاينات</LocalizedLink>
أو
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">اختبارات</LocalizedLink>:

![صورة تظهر تعليق طلب
السحب](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
لا يتم نشر التعليق إلا بعد
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">التحقق
من صحة</LocalizedLink>تشغيل CI الخاص بك.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
إذا كان لديك سير عمل مخصص لا يتم تشغيله عند الالتزام بـ PR، ولكن على سبيل
المثال، تعليق GitHub، فقد تحتاج إلى التأكد من أن متغير `GITHUB_REF` مضبوط على
إما `refs/pull/<pr_number>/merge` أو
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

يمكنك تشغيل الأمر ذي الصلة، مثل `tuist share` ، مع المتغير البيئي المسبوق بـ
`GITHUB_REF`: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number
}}/head" tuist share</code>
<!-- -->
:::
