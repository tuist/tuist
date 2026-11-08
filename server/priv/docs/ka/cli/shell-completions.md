---
{
  "title": "Shell-ის ავტოდასრულება",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "შეიტყვეთ, როგორ მოახდინოთ თქვენი Shell-ის კონფიგურაცია Tuist-ის ბრძანებების ავტომატური დასასრულებლად."
}
---
# გარსის ავტოშევსება {#shell-completions}

თუ Tuist **გლობალურად გაქვთ დაყენებული** (მაგალითად, Homebrew-ის მეშვეობით), შეგიძლიათ დააყენოთ გარსის ავტოშევსება Zsh, Bash და Fish-ისთვის, რათა ბრძანებები და პარამეტრები ავტომატურად შეივსოს.

> [!NOTE]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია არის ინსტალაცია, რომელიც ხელმისაწვდომია თქვენი გარსის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist` შეგიძლიათ გაუშვათ ტერმინალის ნებისმიერი დირექტორიიდან. ეს არის Homebrew-ის ნაგულისხმევი ინსტალაციის მეთოდი.


## Zsh {#zsh}

თუ დაყენებული გაქვთ [oh-my-zsh](https://ohmyz.sh/), უკვე გაქვთ ავტომატურად ჩატვირთვადი შევსების სკრიპტების დირექტორია — `.oh-my-zsh/completions`. დააკოპირეთ თქვენი ახალი შევსების სკრიპტი ამ დირექტორიაში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, შევსების სკრიპტების გზა უნდა დაამატოთ თქვენს ფუნქციურ გზას და ჩართოთ შევსების სკრიპტების ავტოჩატვირთვა. ჯერ დაამატეთ ეს სტრიქონები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით დირექტორია `~/.zsh/completion`-ზე და დააკოპირეთ შევსების სკრიპტი ახალ დირექტორიაში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

თუ დაყენებული გაქვთ [bash-completion](https://github.com/scop/bash-completion), შეგიძლიათ უბრალოდ დააკოპიროთ თქვენი ახალი შევსების სკრიპტი bash-completion-ის დირექტორიაში:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion-ის გარეშე, შევსების სკრიპტი პირდაპირ უნდა წაიკითხოთ (source). ჩაწერეთ ის ისეთ დირექტორიაში, როგორიცაა `~/.bash_completions/`:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

შემდეგ დაამატეთ შემდეგი სტრიქონი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ დააკოპიროთ თქვენი ახალი შევსების სკრიპტი `~/.config/fish/completions/tuist.fish`-ში:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
