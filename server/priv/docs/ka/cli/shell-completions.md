---
{
  "title": "Shell-ის ავტოდასრულება",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "გაიგეთ, როგორ დააკონფიგურიროთ თქვენი shell Tuist-ის ბრძანებების ავტომატურად დასასრულებლად."
}
---
# გარსის ავტოშევსება {#shell-completions}

თუ Tuist **გლობალურად გაქვთ დაინსტალირებული** (მაგ., Homebrew-ით), შეგიძლიათ დააყენოთ გარსის ავტოშევსება Zsh, Bash და Fish-ისთვის, რათა ბრძანებები და პარამეტრები ავტომატურად შეივსოს.

> [!NOTE]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია ნიშნავს ინსტალაციას, რომელიც ხელმისაწვდომია თქვენი გარსის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist`-ის გაშვება ნებისმიერი დირექტორიიდან შეგიძლიათ თქვენს ტერმინალში. ეს არის Homebrew-ის ნაგულისხმევი ინსტალაციის მეთოდი.


## Zsh {#zsh}

თუ [oh-my-zsh](https://ohmyz.sh/) გაქვთ დაინსტალირებული, უკვე გაქვთ დირექტორია ავტომატურად ჩატვირთვადი ავტოშევსების სკრიპტებით — `.oh-my-zsh/completions`. დააკოპირეთ თქვენი ახალი ავტოშევსების სკრიპტი ამ დირექტორიაში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, დაგჭირდებათ ავტოშევსების სკრიპტების გზის დამატება თქვენს ფუნქციის გზაში და ავტოშევსების სკრიპტების ავტოჩატვირთვის ჩართვა. ჯერ დაამატეთ ეს ხაზები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით დირექტორია `~/.zsh/completion`-ზე და დააკოპირეთ ავტოშევსების სკრიპტი ახალ დირექტორიაში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

თუ [bash-completion](https://github.com/scop/bash-completion) გაქვთ დაინსტალირებული, შეგიძლიათ უბრალოდ დააკოპიროთ თქვენი ახალი ავტოშევსების სკრიპტი bash-completion-ის დირექტორიაში:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion-ის გარეშე, დაგჭირდებათ ავტოშევსების სკრიპტის პირდაპირ წყაროდ გამოყენება. ჩაწერეთ ის ისეთ დირექტორიაში, როგორიცაა `~/.bash_completions/`:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

შემდეგ დაამატეთ შემდეგი ხაზი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ დააკოპიროთ თქვენი ახალი ავტოშევსების სკრიპტი `~/.config/fish/completions/tuist.fish`-ში:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
