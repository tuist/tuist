---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# المستندات {#docs}

المصدر:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## ما الغرض منه {#what-it-is-for}

يستضيف موقع الوثائق وثائق منتجات Tuist والمساهمين. تم إنشاؤه باستخدام VitePress.

## كيفية المساهمة {#how-to-contribute}

### قم بالإعداد محليًا {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### بيانات اختيارية تم إنشاؤها {#optional-generated-data}

نقوم بتضمين بعض البيانات التي تم إنشاؤها في المستندات:

- بيانات مرجعية CLI: `mise run generate-cli-docs`
- بيانات مرجعية لمشروع البيان: `mise run generate-manifests-docs`

هذه خطوات اختيارية. يتم عرض المستندات بدونها، لذا لا تقم بتنفيذها إلا عند الحاجة
إلى تحديث المحتوى الذي تم إنشاؤه.
