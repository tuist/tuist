---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# التسجيل {#logging}

يقوم CLI بتسجيل الرسائل داخلياً لمساعدتك في تشخيص المشاكل.

## تشخيص المشكلات باستخدام السجلات {#diagnose-issues-using-logs}

إذا لم ينتج عن استدعاء الأمر النتائج المرجوة، يمكنك تشخيص المشكلة من خلال فحص
السجلات. تقوم CLI بإعادة توجيه السجلات إلى [OSLog]
(https://developer.apple.com/documentation/os/oslog) ونظام الملفات.

في كل عملية تشغيل، ينشئ ملف سجل على `$ XDG_STATE_HOME/UIST/logs/{uuid}.log` حيث
`$ XDG_STATE_HOME` يأخذ القيمة `~/.local/state` إذا لم يتم تعيين متغير البيئة.
ويمكنك أيضًا استخدام `$ TUIST_XDG_STATE_STATE_HOME` لتعيين دليل حالة خاص بتويست،
والذي يأخذ الأسبقية على `$ XDG_STATE_HOME`.

::: tip
تعرف على المزيد حول تنظيم دليل تويست وكيفية تكوين الدلائل المخصصة في وثائق <LocalizedLink href="/cli/directories">الدلائل</LocalizedLink>.
:::

بشكل افتراضي، يقوم CLI بإخراج مسار السجلات عند خروج التنفيذ بشكل غير متوقع. إذا
لم يفعل ذلك، يمكنك العثور على السجلات في المسار المذكور أعلاه (أي أحدث ملف سجل).

::: warning
لا يتم تنقيح المعلومات الحساسة، لذا كن حذراً عند مشاركة السجلات.
:::

### التكامل المستمر {#diagnose-issues-using-logs-ci}

في CI، حيث تكون البيئات قابلة للتصرف، قد ترغب في تكوين خط أنابيب CI لتصدير سجلات
Tuist. تصدير القطع الأثرية هي إمكانية مشتركة عبر خدمات CI، ويعتمد التكوين على
الخدمة التي تستخدمها. على سبيل المثال، في GitHub Actions، يمكنك استخدام الإجراء
`actions/upload-artifact` لتحميل السجلات كقطعة أثرية:

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

### تصحيح أخطاء البرنامج الخفي للتخزين المؤقت {#cache-daemon-debugging}

لتصحيح المشاكل المتعلقة بذاكرة التخزين المؤقت، يسجل تويست عمليات البرنامج الخفي
لذاكرة التخزين المؤقت باستخدام `os_log` مع النظام الفرعي `dev.tuist.cache`.
يمكنك بث هذه السجلات في الوقت الفعلي باستخدام:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

تظهر هذه السجلات أيضًا في Console.app عن طريق التصفية للنظام الفرعي
`.tuist.cache`. يوفر هذا معلومات مفصلة حول عمليات ذاكرة التخزين المؤقت، والتي
يمكن أن تساعد في تشخيص مشاكل التحميل والتنزيل والاتصال في ذاكرة التخزين المؤقت.
