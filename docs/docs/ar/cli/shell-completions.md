---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

إذا كان لديك تويست **مثبتًا عالميًا** (على سبيل المثال، عبر Homebrew)، يمكنك
تثبيت إكمال الصدفة لباش و Zsh للإكمال التلقائي للأوامر والخيارات.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
التثبيت العام هو تثبيت متاح في متغير البيئة `$PATH` الخاص بالصدفة الخاصة بك. هذا
يعني أنه يمكنك تشغيل `tuist` من أي دليل في جهازك الطرفي. هذه هي طريقة التثبيت
الافتراضية لـ Homebrew.
<!-- -->
:::

#### زش {#zsh}

إذا كان لديك [oh-my-zsh] (https://ohmyz.sh/) مثبتًا لديك، فلديك بالفعل دليل
لنصوص الإكمال النصية التي يتم تحميلها تلقائيًا - `.oh-my-zsh/completions`. انسخ
نص الإكمال الجديد إلى ملف جديد في هذا الدليل يسمى `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

بدون `oh-my-zsh` ، ستحتاج إلى إضافة مسار لنصوص الإكمال إلى مسار الوظيفة لديك،
وتشغيل التحميل التلقائي لنصوص الإكمال. أولاً، أضف هذه الأسطر إلى `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

بعد ذلك، أنشئ دليلاً في `~/.zsh/completion` وانسخ نص الإكمال وانسخ نص الإكمال
إلى الدليل الجديد، مرة أخرى في ملف يسمى `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### باش {#bash}

إذا كان لديك [bash-completion] (https://github.com/scop/bash-completion) مثبتًا
لديك، يمكنك فقط نسخ نص الإكمال الجديد إلى الملف
`/usr/local/etc/bash_completion.d/tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

بدون إكمال bash-completion، ستحتاج إلى مصدر البرنامج النصي للإكمال مباشرةً.
انسخه إلى دليل مثل `~/.bash_completions/` ، ثم أضف السطر التالي إلى
`~/.bash_profile` أو `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### السمك {#fish}

إذا كنت تستخدم [صدفة السمك] (https://fishshell.com)، يمكنك نسخ نص الإكمال الجديد
إلى `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
