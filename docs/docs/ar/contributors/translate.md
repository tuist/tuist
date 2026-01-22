---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# ترجم {#translate}

يمكن أن تشكل اللغات عوائق أمام الفهم. نريد أن نتأكد من أن Tuist متاح لأكبر عدد
ممكن من الأشخاص. إذا كنت تتحدث لغة لا يدعمها Tuist، يمكنك مساعدتنا من خلال ترجمة
مختلف أجزاء Tuist.

نظرًا لأن صيانة الترجمات تتطلب جهدًا مستمرًا، فإننا نضيف لغات جديدة كلما وجدنا
متبرعين مستعدين لمساعدتنا في صيانتها. اللغات التالية مدعومة حاليًا:

- الإنجليزية
- الكورية
- اليابانية
- الروسية
- الصينية
- الإسبانية
- البرتغالية

::: tip REQUEST A NEW LANGUAGE
<!-- -->
إذا كنت تعتقد أن Tuist سيستفيد من دعم لغة جديدة، فيرجى إنشاء [موضوع جديد في
منتدى المجتمع](https://community.tuist.io/c/general/4) لمناقشته مع المجتمع.
<!-- -->
:::

## كيفية الترجمة {#how-to-translate}

لدينا نسخة من [Weblate](https://weblate.org/en-gb/) تعمل على
[translate.tuist.dev](https://translate.tuist.dev). يمكنك التوجه إلى
[المشروع](https://translate.tuist.dev/engage/tuist/) وإنشاء حساب والبدء في
الترجمة.

يتم مزامنة الترجمات مرة أخرى إلى مستودع المصدر باستخدام طلبات السحب GitHub التي
سيقوم المشرفون بمراجعتها ودمجها.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
يقوم Weblate بتقسيم الملفات لربط اللغات المصدر واللغات الهدف. إذا قمت بتعديل
اللغة المصدر، فسوف تكسر الارتباط، وقد تؤدي المطابقة إلى نتائج غير متوقعة.
<!-- -->
:::

## إرشادات {#guidelines}

فيما يلي الإرشادات التي نتبعها عند الترجمة.

### حاويات مخصصة وتنبيهات GitHub {#custom-containers-and-github-alerts}

عند ترجمة [custom
containers](https://vitepress.dev/guide/markdown#custom-containers) ، قم بترجمة
العنوان والمحتوى فقط **ولكن لا تقم بترجمة نوع التنبيه**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### عناوين العناوين {#heading-titles}

عند ترجمة العناوين، قم بترجمة العنوان فقط دون الرمز التعريفي. على سبيل المثال،
عند ترجمة العنوان التالي:

```markdown
# Add dependencies {#add-dependencies}
```

يجب ترجمته على النحو التالي (لاحظ أن المعرف لم يُترجم):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
