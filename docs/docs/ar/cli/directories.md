---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# الدلائل {#directories}

ينظم Tuist ملفاته عبر عدة أدلة على نظامك، وفقًا لمواصفات [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
يوفر هذا طريقة نظيفة وقياسية لإدارة ملفات التكوين والذاكرة المؤقتة والحالة.

## متغيرات البيئة المدعومة {#supported-environment-variables}

يدعم Tuist كلاً من متغيرات XDG القياسية والمتغيرات المسبوقة ببادئة خاصة بـ
Tuist. المتغيرات الخاصة بـ Tuist (المسبوقة ببادئة `TUIST_`) لها الأسبقية، مما
يتيح لك تكوين Tuist بشكل منفصل عن التطبيقات الأخرى.

### دليل التكوين {#configuration-directory}

**متغيرات البيئة:**
- `TUIST_XDG_CONFIG_HOME` (له الأسبقية)
- `XDG_CONFIG_HOME`

**الافتراضي:** `~/.config/tuist`

**تستخدم في:**
- بيانات اعتماد الخادم (`credentials/{host}.json`)

**مثال:**
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
- `TUIST_XDG_CACHE_HOME` (تأخذ الأسبقية)
- `XDG_CACHE_HOME`

**الافتراضي:** `~/.cache/tuist`

**تستخدم في:**
- **المكونات الإضافية**: تم تنزيل وتجميع ذاكرة التخزين المؤقتة للمكونات الإضافية
- **ProjectDescriptionHelpers**: مساعدات وصف المشروع المجمعة
- **البيانات**: ملفات البيانات المخزنة مؤقتًا
- **المشاريع**: تم إنشاء ذاكرة التخزين المؤقتة لمشروع الأتمتة
- **EditProjects**: ذاكرة التخزين المؤقت لأمر التحرير
- **تشغيل**: اختبار وبناء بيانات تحليلات التشغيل
- **الملفات الثنائية**: إنشاء ملفات ثنائية (غير قابلة للمشاركة عبر البيئات)
- **SelectiveTests**: ذاكرة التخزين المؤقت للاختبارات الانتقائية

**مثال:**
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
- `TUIST_XDG_STATE_HOME` (تأخذ الأسبقية)
- `XDG_STATE_HOME`

**الافتراضي:** `~/.local/state/tuist`

**تستخدم في:**
- **السجلات**: ملفات السجلات (`logs/{uuid}.log`)
- **قفل ملفات**: ملفات قفل المصادقة (`{handle}.sock`)

**مثال:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## ترتيب الأسبقية {#precedence-order}

عند تحديد الدليل الذي سيتم استخدامه، يتحقق Tuist من متغيرات البيئة بالترتيب
التالي:

1. **متغير خاص بـ Tuist** (على سبيل المثال، `TUIST_XDG_CONFIG_HOME`)
2. **متغير XDG القياسي** (على سبيل المثال، `XDG_CONFIG_HOME`)
3. **الموقع الافتراضي** (على سبيل المثال، `~/.config/tuist`)

هذا يتيح لك:
- استخدم متغيرات XDG القياسية لتنظيم جميع تطبيقاتك بشكل متسق
- استبدل المتغيرات الخاصة بـ Tuist عندما تحتاج إلى مواقع مختلفة لـ Tuist
- اعتمد على الإعدادات الافتراضية المعقولة دون أي تكوين

## حالات الاستخدام الشائعة {#common-use-cases}

### عزل Tuist لكل مشروع {#isolating-tuist-per-project}

قد ترغب في عزل ذاكرة التخزين المؤقتة لـ Tuist وحالة كل مشروع:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### بيئات CI/CD {#ci-cd-environments}

في بيئات CI، قد ترغب في استخدام دلائل مؤقتة:

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

### تصحيح الأخطاء باستخدام دلائل معزولة {#debugging-with-isolated-directories}

عند تصحيح الأخطاء، قد ترغب في البدء من الصفر:

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
