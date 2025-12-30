---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# ترجمة {#translate}

يمكن أن تكون اللغات عائقاً أمام الفهم. نريد التأكد من أن تويست متاح لأكبر عدد
ممكن من الأشخاص. إذا كنت تتحدث لغة لا تدعمها تويست، فيمكنك مساعدتنا من خلال
ترجمة الأسطح المختلفة لتويست.

نظرًا لأن الحفاظ على الترجمات هو جهد مستمر، فإننا نضيف لغات كلما وجدنا مساهمين
على استعداد لمساعدتنا في الحفاظ عليها. اللغات التالية مدعومة حاليًا:

- اللغة الإنجليزية
- كوري
- ياباني
- الروسية
- صيني
- الإسبانية
- البرتغالية

::: tip REQUEST A NEW LANGUAGE
<!-- -->
إذا كنت تعتقد أن تويست ستستفيد من دعم لغة جديدة، يرجى إنشاء [موضوع جديد في منتدى
المجتمع] (https://community.tuist.io/c/general/4) لمناقشته مع المجتمع.
<!-- -->
:::

## كيفية الترجمة {#how-to-translate}

لدينا نسخة من [Weblate] (https://weblate.org/en-gb/) تعمل على
[translate.tuist.dev] (https://translate.tuist.dev). يمكنك التوجه إلى
[المشروع](https://translate.tuist.dev/engage/tuist/)، وإنشاء حساب، وبدء الترجمة.

تتم مزامنة الترجمات مرة أخرى إلى المستودع المصدر باستخدام طلبات سحب GitHub التي
سيقوم المشرفون بمراجعتها ودمجها.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
يقوم Weblate بتقسيم الملفات لربط اللغة المصدر واللغة الهدف. إذا قمت بتعديل اللغة
المصدر، فسوف تكسر الربط، وقد تسفر التسوية عن نتائج غير متوقعة.
<!-- -->
:::

## الإرشادات {#guidelines}

فيما يلي الإرشادات التي نتبعها عند الترجمة.

### الحاويات المخصصة وتنبيهات GitHub {#custom-containers-and-github-alerts}

عند ترجمة [الحاويات المخصصة]
(https://vitepress.dev/guide/markdown#custom-containers) فقط ترجمة العنوان
والمحتوى **ولكن ليس نوع التنبيه**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### عناوين العناوين {#heading-titles}

عند ترجمة العناوين، قم بترجمة العنوان فقط وليس المعرف. على سبيل المثال، عند
ترجمة العنوان التالي:

```markdown
# Add dependencies {#add-dependencies}
```

يجب ترجمتها على النحو التالي (لاحظ أن المعرف غير مترجم):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
