---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

إذا كان لديك Tuist **مثبتًا بشكل عام** (على سبيل المثال، عبر Homebrew)، فيمكنك
تثبيت إكمالات shell لـ Bash و Zsh لإكمال الأوامر والخيارات تلقائيًا.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
التثبيت الشامل هو تثبيت متاح في متغير بيئة $PATH` في شل `. هذا يعني أنه يمكنك
تشغيل `tuist` من أي دليل في محطتك الطرفية. هذه هي طريقة التثبيت الافتراضية لـ
Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

إذا كان لديك [oh-my-zsh](https://ohmyz.sh/) مثبتًا، فأنت تمتلك بالفعل دليلًا
لبرامج النصوص النهائية التي يتم تحميلها تلقائيًا — `.oh-my-zsh/completions`.
انسخ برنامج النص النهائي الجديد إلى ملف جديد في هذا الدليل يسمى `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

بدون `oh-my-zsh` ، ستحتاج إلى إضافة مسار لبرامج إكمال النصوص إلى مسار الوظيفة
الخاص بك، وتشغيل التحميل التلقائي لبرامج إكمال النصوص. أولاً، أضف هذه الأسطر إلى
`~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

بعد ذلك، أنشئ دليلًا في `~/.zsh/completion` وانسخ البرنامج النصي للإكمال إلى
الدليل الجديد، مرة أخرى في ملف يسمى `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

إذا كان لديك [bash-completion](https://github.com/scop/bash-completion) مثبتًا،
فيمكنك فقط نسخ البرنامج النصي الجديد لإكمال الكلمات إلى الملف
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

بدون ميزة إكمال bash، ستحتاج إلى الحصول على البرنامج النصي للإكمال مباشرة. انسخه
إلى دليل مثل `~/.bash_completions/` ، ثم أضف السطر التالي إلى `~/.bash_profile`
أو `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### سمك {#fish}

إذا كنت تستخدم [fish shell](https://fishshell.com)، يمكنك نسخ البرنامج النصي
الجديد لإكمال الكلمات إلى `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
