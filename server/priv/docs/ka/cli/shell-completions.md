---
{
  "title": "Shell-ის ავტოშევსება",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "შეიტყვეთ, როგორ დააკონფიგურიროთ თქვენი shell ისე, რომ Tuist-ის ბრძანებები ავტომატურად შეავსოს."
}
---
# გარსის ავტოდასრულება

თუ Tuist **გლობალურად არის დაინსტალირებული** (მაგ., Homebrew-ის საშუალებით), შეგიძლიათ დააყენოთ გარსის ავტოდასრულება Bash-ისა და Zsh-ისთვის, რათა ბრძანებები და პარამეტრები ავტომატურად დასრულდეს.

> [!WARNING]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია ნიშნავს ინსტალაციას, რომელიც ხელმისაწვდომია თქვენი გარსის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist` შეგიძლიათ გაუშვათ ტერმინალის ნებისმიერი დირექტორიიდან. ეს არის Homebrew-ისთვის ნაგულისხმევი ინსტალაციის მეთოდი.


#### Zsh {#zsh}

თუ [oh-my-zsh](https://ohmyz.sh/) გაქვთ დაინსტალირებული, უკვე გაქვთ დირექტორია ავტომატურად ჩატვირთვადი დასრულების სკრიპტებისთვის — `.oh-my-zsh/completions`. გადაიტანეთ თქვენი ახალი დასრულების სკრიპტი ამ დირექტორიაში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, დასრულების სკრიპტების გზა უნდა დაამატოთ თქვენს ფუნქციების გზას და ჩართოთ დასრულების სკრიპტების ავტოჩატვირთვა. ჯერ დაამატეთ ეს სტრიქონები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით დირექტორია `~/.zsh/completion`-ში და გადაიტანეთ დასრულების სკრიპტი ახალ დირექტორიაში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

თუ [bash-completion](https://github.com/scop/bash-completion) გაქვთ დაინსტალირებული, შეგიძლიათ უბრალოდ გადაიტანოთ თქვენი ახალი დასრულების სკრიპტი ფაილში `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion-ის გარეშე, დასრულების სკრიპტი პირდაპირ უნდა ჩატვირთოთ. გადაიტანეთ ის დირექტორიაში, როგორიცაა `~/.bash_completions/`, და შემდეგ დაამატეთ შემდეგი სტრიქონი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ გადაიტანოთ თქვენი ახალი დასრულების სკრიპტი `~/.config/fish/completions/tuist.fish`-ში:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
