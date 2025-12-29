---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# الدلائل {#directories}

ينظم Tuist ملفاته عبر عدة دلائل على نظامك، باتباع [مواصفات الدليل الأساسي لـ
XDG]
(https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
يوفر هذا طريقة قياسية ونظيفة لإدارة ملفات التكوين وذاكرة التخزين المؤقت وملفات
الحالة.

## متغيرات البيئة المدعومة {#supported-environment-variables}

يدعم تويست كلاً من متغيرات XDG القياسية والمتغيرات المسبقة الخاصة بتويست. تحظى
المتغيرات الخاصة بتويست (المسبوقة ببادئة `TUIST_`) بالأولوية، مما يسمح لك بتهيئة
تويست بشكل منفصل عن التطبيقات الأخرى.

### دليل التكوين {#configuration-directory}

**متغيرات البيئة:**
- `TUIST_XDG_CONFIG_HOME` (له الأسبقية)
- `xdg_config_home`

**الإعداد الافتراضي:** `~/.config/tuist`

**تُستخدم لـ**
- بيانات اعتماد الخادم (`بيانات الاعتماد/{المضيف}.json`)

**مثال على ذلك:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### دليل ذاكرة التخزين المؤقت {#cache-directory}

**متغيرات البيئة:**
- `TUIST_XDG_CACHE_HOME` (له الأسبقية)
- `XDG_CACHE_HOME`

**الإعداد الافتراضي:** `~/.cache/tuist الافتراضي`

**تُستخدم لـ**
- **الإضافات**: تم تنزيل وتجميع ذاكرة التخزين المؤقت للمكونات الإضافية
- **مساعدو وصف المشروع**: أدوات مساعدة وصف المشروع المجمعة
- **بيانات**: ملفات البيان المخزنة مؤقتًا
- **المشاريع**: ذاكرة التخزين المؤقت لمشروع الأتمتة المُنشأة
- **EditProjects**: ذاكرة التخزين المؤقت لأمر التحرير
- **التشغيلات**: اختبار وبناء بيانات تحليلات التشغيل
- **الثنائيات**: بناء ثنائيات القطع الأثرية (غير قابلة للمشاركة عبر البيئات)
- **اختبارات انتقائية**: ذاكرة التخزين المؤقت للاختبارات الانتقائية

**مثال على ذلك:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### دليل الولاية {#state-directory}

**متغيرات البيئة:**
- `TUIST_XDG_STATE_STATE_HOME` (له الأسبقية)
- `XDG_STATE_HOME`

**الإعداد الافتراضي:** ` ~/.loc/.local/state/tuist`

**تُستخدم لـ**
- **السجلات**: ملفات السجلات (`logs/{uuid}.log`)
- **أقفال**: ملفات قفل المصادقة (`{handle}.sock`)

**مثال على ذلك:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## ترتيب الأسبقية {#precedence-order}

عند تحديد الدليل الذي يجب استخدامه، يتحقق تويست من متغيرات البيئة بالترتيب
التالي:

1. **المتغير الخاص بالتويست** (على سبيل المثال، `TUIST_XDG_CONFIG_HOME`)
2. **متغير XDG القياسي** (على سبيل المثال، `XDG_CONFIG_HOME`)
3. **الموقع الافتراضي** (على سبيل المثال، `~/.config/tuist`)

يسمح لك ذلك بما يلي:
- استخدام متغيرات XDG القياسية لتنظيم جميع تطبيقاتك بشكل متسق
- التجاوز بالمتغيرات الخاصة بتويست عندما تحتاج إلى مواقع مختلفة لتويست
- الاعتماد على الإعدادات الافتراضية المعقولة دون أي تهيئة

## حالات الاستخدام الشائعة {#common-use-cases}

### عزل تويست لكل مشروع {#isolating-tuist-per-project}

قد ترغب في عزل ذاكرة التخزين المؤقت لـ Tuist وحالة كل مشروع:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### بيئات CI/CDD {#ci-cd-environments}

في بيئات CI، قد ترغب في استخدام الدلائل المؤقتة:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### تصحيح الأخطاء مع الدلائل المعزولة {#debugging-with-isolated-directories}

عند تصحيح المشكلات، قد تحتاج إلى سجل نظيف:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
