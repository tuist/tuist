---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# تسجيل الدخول {#logging}

يقوم CLI بتسجيل الرسائل داخليًا لمساعدتك في تشخيص المشكلات.

## تشخيص المشكلات باستخدام السجلات {#diagnose-issues-using-logs}

إذا لم يسفر استدعاء الأمر عن النتائج المرجوة، يمكنك تشخيص المشكلة عن طريق فحص
السجلات. يقوم CLI بإعادة توجيه السجلات إلى
[OSLog](https://developer.apple.com/documentation/os/oslog) ونظام الملفات.

في كل عملية تشغيل، يتم إنشاء ملف سجل في `$XDG_STATE_HOME/tuist/logs/{uuid}.log`
حيث `$XDG_STATE_HOME` تأخذ القيمة `~/.local/state` إذا لم يتم تعيين متغير
البيئة. يمكنك أيضًا استخدام `$TUIST_XDG_STATE_HOME` لتعيين دليل حالة خاص بـ
Tuist، والذي له الأسبقية على `$XDG_STATE_HOME`.

:::: إكرامية
<!-- -->
تعرف على المزيد حول تنظيم دليل Tuist وكيفية تكوين أدلة مخصصة في
<LocalizedLink href="/cli/directories">وثائق الأدلة</LocalizedLink>.
<!-- -->
:::

بشكل افتراضي، يقوم CLI بإخراج مسار السجلات عندما ينتهي التنفيذ بشكل غير متوقع.
إذا لم يحدث ذلك، يمكنك العثور على السجلات في المسار المذكور أعلاه (أي ملف السجل
الأحدث).

:::: تحذير
<!-- -->
المعلومات الحساسة لا يتم حجبها، لذا توخ الحذر عند مشاركة السجلات.
<!-- -->
:::

### التكامل المستمر {#diagnose-issues-using-logs-ci}

في CI، حيث البيئات قابلة للتصرف، قد ترغب في تكوين خط أنابيب CI لتصدير سجلات
Tuist. يعد تصدير الأرتفاعات ميزة شائعة في خدمات CI، ويعتمد التكوين على الخدمة
التي تستخدمها. على سبيل المثال، في GitHub Actions، يمكنك استخدام الإجراء
`actions/upload-artifact` لتحميل السجلات كأرتفاع:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### تصحيح أخطاء برنامج الخدمة الخفية {#cache-daemon-debugging}

لتصحيح المشكلات المتعلقة بالذاكرة المؤقتة، يسجل Tuist عمليات برنامج الخدمة
المؤقتة باستخدام `os_log` مع النظام الفرعي `dev.tuist.cache`. يمكنك بث هذه
السجلات في الوقت الفعلي باستخدام:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

يمكن أيضًا رؤية هذه السجلات في Console.app من خلال تصفية نظام فرعي
`dev.tuist.cache`. يوفر هذا معلومات مفصلة حول عمليات ذاكرة التخزين المؤقت، مما
يساعد في تشخيص مشكلات تحميل ذاكرة التخزين المؤقت وتنزيلها والاتصال.
