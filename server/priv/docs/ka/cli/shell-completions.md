---
{
  "title": "Shell-ის დასრულებები",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "გაიგეთ, როგორ მოახდინოთ თქვენი shell-ის კონფიგურაცია Tuist-ის ბრძანებების ავტომატური დასასრულებისთვის."
}
---
# Shell-ის ავტოშევსება

თუ Tuist **გლობალურად გაქვთ დაინსტალირებული** (მაგალითად, Homebrew-ით), შეგიძლიათ დააინსტალიროთ Shell-ის ავტოშევსება Bash-ისა და Zsh-ისთვის ბრძანებებისა და პარამეტრების ავტომატური შევსების მიზნით.

> [!WARNING]
> **რა არის გლობალური ინსტალაცია**
>
> გლობალური ინსტალაცია ნიშნავს ინსტალაციას, რომელიც ხელმისაწვდომია თქვენი Shell-ის `$PATH` გარემოს ცვლადში. ეს ნიშნავს, რომ `tuist`-ის გაშვება შეგიძლიათ ტერმინალის ნებისმიერი დირექტორიიდან. ეს არის Homebrew-ის საწყისი ინსტალაციის მეთოდი.


#### Zsh {#zsh}

თუ გაქვთ დაინსტალირებული [oh-my-zsh](https://ohmyz.sh/), უკვე გაქვთ ავტომატურად ჩატვირთვადი ავტოშევსების სკრიპტების დირექტორია — `.oh-my-zsh/completions`. დააკოპირეთ თქვენი ახალი ავტოშევსების სკრიპტი ამ დირექტორიაში ახალ ფაილში სახელით `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`-ის გარეშე, დაგჭირდებათ ავტოშევსების სკრიპტების გზის დამატება თქვენს ფუნქციების გზაზე და ავტოშევსების სკრიპტების ავტოჩატვირთვის ჩართვა. ჯერ დაამატეთ ეს სტრიქონები `~/.zshrc`-ში:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

შემდეგ, შექმენით დირექტორია `~/.zsh/completion`-ზე და დააკოპირეთ ავტოშევსების სკრიპტი ახალ დირექტორიაში, ისევ ფაილში სახელით `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

თუ გაქვთ დაინსტალირებული [bash-completion](https://github.com/scop/bash-completion), შეგიძლიათ უბრალოდ დააკოპიროთ თქვენი ახალი ავტოშევსების სკრიპტი ფაილში `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion-ის გარეშე, დაგჭირდებათ ავტოშევსების სკრიპტის პირდაპირ წყაროდან ჩატვირთვა. დააკოპირეთ ის ისეთ დირექტორიაში, როგორიცაა `~/.bash_completions/`, და შემდეგ დაამატეთ შემდეგი სტრიქონი `~/.bash_profile`-ში ან `~/.bashrc`-ში:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

თუ იყენებთ [fish shell](https://fishshell.com)-ს, შეგიძლიათ დააკოპიროთ თქვენი ახალი ავტოშევსების სკრიპტი `~/.config/fish/completions/tuist.fish`-ში:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
