---
{
  "title": "Shell-ის ავტოდასრულება",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "შეიტყვეთ, როგორ დააკონფიგურიროთ თქვენი shell, რათა ავტომატურად ასრულებდეს Tuist-ის ბრძანებებს."
}
---
# გარსის ავტოდასრულება

თუ Tuist **გლობალურად გაქვთ დაინსტალირებული** (მაგალითად, Homebrew-ით), შეგიძლიათ დააყენოთ გარსის ავტოდასრულება Bash-ისა და Zsh-ისთვის, რათა ბრძანებები და პარამეტრები ავტომატურად ივსებოდეს.

> [!WARNING]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია ნიშნავს ინსტალაციას, რომელიც ხელმისაწვდომია თქვენი გარსის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist`-ის გაშვება ტერმინალში ნებისმიერი საქაღალდიდან შეგიძლიათ. ეს არის Homebrew-ის მიერ გამოყენებული ინსტალაციის ნაგულისხმევი მეთოდი.


#### Zsh {#zsh}

თუ [oh-my-zsh](https://ohmyz.sh/) გაქვთ დაინსტალირებული, უკვე გაქვთ ავტომატურად ჩატვირთვადი დასრულების სკრიპტების საქაღალდე — `.oh-my-zsh/completions`. დააკოპირეთ თქვენი ახალი დასრულების სკრიპტი ამ საქაღალდეში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, დასრულების სკრიპტების გზა ფუნქციების გზაში უნდა დაამატოთ და ჩართოთ დასრულების სკრიპტების ავტოჩატვირთვა. ჯერ დაამატეთ ეს სტრიქონები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით საქაღალდე `~/.zsh/completion`-ზე და დააკოპირეთ დასრულების სკრიპტი ახალ საქაღალდეში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

თუ [bash-completion](https://github.com/scop/bash-completion) გაქვთ დაინსტალირებული, შეგიძლიათ პირდაპირ დააკოპიროთ თქვენი ახალი დასრულების სკრიპტი ფაილში `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion-ის გარეშე, დასრულების სკრიპტი პირდაპირ უნდა წარმოადგინოთ (source). დააკოპირეთ ის ისეთ საქაღალდეში, როგორიცაა `~/.bash_completions/`, და შემდეგ დაამატეთ შემდეგი სტრიქონი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ დააკოპიროთ თქვენი ახალი დასრულების სკრიპტი `~/.config/fish/completions/tuist.fish`-ზე:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
