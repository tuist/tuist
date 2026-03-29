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
التثبيت العام هو التثبيت المتاح في متغير بيئة $PATH `` الخاص بـ shell الخاص بك.
هذا يعني أنه يمكنك تشغيل `tuist` من أي دليل في محطة العمل الخاصة بك. هذه هي
طريقة التثبيت الافتراضية لـ Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

إذا كان لديك [oh-my-zsh](https://ohmyz.sh/) مثبتًا، فأنت تمتلك بالفعل دليلًا
لنصوص إكمال يتم تحميلها تلقائيًا — `.oh-my-zsh/completions`. انسخ نص الإكمال
الجديد إلى ملف جديد في ذلك الدليل باسم `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

بدون `oh-my-zsh` ، ستحتاج إلى إضافة مسار لبرامج نصية الإكمال إلى مسار الوظائف
الخاص بك، وتشغيل التحميل التلقائي لبرامج نصية الإكمال. أولاً، أضف هذه الأسطر إلى
`~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

بعد ذلك، أنشئ دليلًا في `~/.zsh/completion` وانسخ البرنامج النصي الخاص بإكمال
الكلمات إلى الدليل الجديد، مرة أخرى في ملف باسم `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

إذا كان لديك [bash-completion](https://github.com/scop/bash-completion) مثبتًا،
يمكنك ببساطة نسخ نصك البرمجي الجديد لإكمال الأوامر إلى الملف
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

بدون bash-completion، ستحتاج إلى تحميل البرنامج النصي الخاص بالإكمال مباشرةً.
انسخه إلى دليل مثل `~/.bash_completions/` ، ثم أضف السطر التالي إلى
`~/.bash_profile` أو `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### سمكة {#fish}

إذا كنت تستخدم [fish shell](https://fishshell.com)، فيمكنك نسخ نصوص الإكمال
الجديدة إلى `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
