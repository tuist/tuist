---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# تثبيت Tuist {#install-tuist}

يتكون Tuist CLI من ملف قابل للتنفيذ وأطر عمل ديناميكية ومجموعة من الموارد (على
سبيل المثال، القوالب). على الرغم من أنه يمكنك إنشاء Tuist يدويًا من
[المصادر](https://github.com/tuist/tuist), **، فإننا نوصي باستخدام إحدى طرق
التثبيت التالية لضمان تثبيت صحيح.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::: المعلومات
<!-- -->
يُوصى باستخدام Mise كبديل لـ [Homebrew](https://brew.sh) إذا كنت جزءًا من فريق
أو مؤسسة تحتاج إلى ضمان وجود إصدارات محددة من الأدوات في بيئات مختلفة.
<!-- -->
:::

يمكنك تثبيت Tuist من خلال أي من الأوامر التالية:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

لاحظ أنه على عكس أدوات مثل Homebrew، التي تقوم بتثبيت وتنشيط إصدار واحد من
الأداة على مستوى عالمي، فإن **Mise تتطلب تنشيط إصدار** إما على مستوى عالمي أو
على نطاق مشروع. ويتم ذلك عن طريق تشغيل `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

يمكنك تثبيت Tuist باستخدام [Homebrew](https://brew.sh)
و[صيغنا](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
يمكنك التحقق من أن الملفات الثنائية للتثبيت الخاص بك قد تم إنشاؤها بواسطتنا عن
طريق تشغيل الأمر التالي، الذي يتحقق مما إذا كان فريق الشهادة هو `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
