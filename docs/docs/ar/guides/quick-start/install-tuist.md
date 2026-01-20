---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# تثبيت تويست {#install-tuist}

تتألف واجهة برمجة تويست CLI من ملف قابل للتنفيذ، وأطر ديناميكية، ومجموعة من
الموارد (على سبيل المثال، القوالب). على الرغم من أنه يمكنك بناء تويست يدويًا من
[المصادر] (https://github.com/tuist/tuist)، **نوصي باستخدام إحدى طرق التثبيت
التالية لضمان تثبيت صالح.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::: المعلومات
<!-- -->
يعد Mise بديلاً موصى به لـ [Homebrew] (https://brew.sh) إذا كنت فريقًا أو مؤسسة
تحتاج إلى ضمان إصدارات حتمية من الأدوات عبر بيئات مختلفة.
<!-- -->
:::

يمكنك تثبيت تويست من خلال أي من الأوامر التالية:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

لاحظ أنه على عكس أدوات مثل Homebrew، التي تقوم بتثبيت وتفعيل إصدار واحد من
الأداة على مستوى العالم، يتطلب **Mise تفعيل إصدار** إما على مستوى العالم أو على
نطاق مشروع ما. يتم ذلك عن طريق تشغيل `mise استخدم`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">البيرة المنزلية</a> {#recommended-homebrew}

يمكنك تثبيت تويست باستخدام [Homebrew] (https://brew.sh) و [صيغنا]
(https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
يمكنك التحقق من أن ثنائيات التثبيت الخاصة بك قد تم بناؤها من خلال تشغيل الأمر
التالي، والذي يتحقق مما إذا كان فريق الشهادة هو `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
