---
{
  "title": "Shell-ის ავტოშევსება",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "გაიგეთ, როგორ დააკონფიგურიროთ თქვენი shell Tuist-ის ბრძანებების ავტომატურად შესავსებად."
}
---
# Shell-ის ავტოდასრულება {#shell-completions}

თუ Tuist **გლობალურად გაქვთ დაყენებული** (მაგალითად, Homebrew-ის საშუალებით), შეგიძლიათ დააინსტალიროთ Shell-ის ავტოდასრულება Zsh, Bash და Fish-ისთვის, რათა ბრძანებები და პარამეტრები ავტომატურად დასრულდეს.

> [!NOTE]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია არის ინსტალაცია, რომელიც ხელმისაწვდომია თქვენი Shell-ის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist`-ის გაშვება ნებისმიერი დირექტორიიდან შეგიძლიათ თქვენს ტერმინალში. ეს არის Homebrew-ის ინსტალაციის ნაგულისხმევი მეთოდი.


## Zsh {#zsh}

თუ [oh-my-zsh](https://ohmyz.sh/) გაქვთ დაყენებული, უკვე გაქვთ ავტომატურად ჩატვირთვადი დასრულების სკრიპტების დირექტორია — `.oh-my-zsh/completions`. დააკოპირეთ თქვენი ახალი დასრულების სკრიპტი ამ დირექტორიაში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, დასრულების სკრიპტების გზა უნდა დაამატოთ თქვენს ფუნქციების გზას და ჩართოთ დასრულების სკრიპტების ავტოჩატვირთვა. ჯერ დაამატეთ ეს ხაზები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით დირექტორია `~/.zsh/completion`-ში და დააკოპირეთ დასრულების სკრიპტი ახალ დირექტორიაში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

თუ [bash-completion](https://github.com/scop/bash-completion) გაქვთ დაყენებული, შეგიძლიათ უბრალოდ დააკოპიროთ თქვენი ახალი დასრულების სკრიპტი bash-completion-ის დირექტორიაში:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion-ის გარეშე, დასრულების სკრიპტი პირდაპირ უნდა ჩატვირთოთ (source). ჩაწერეთ ის ისეთ დირექტორიაში, როგორიცაა `~/.bash_completions/`:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

შემდეგ დაამატეთ შემდეგი ხაზი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ დააკოპიროთ თქვენი ახალი დასრულების სკრიპტი `~/.config/fish/completions/tuist.fish`-ში:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
