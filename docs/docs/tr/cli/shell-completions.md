---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell tamamlamaları

Tuist **'ı global olarak** (örneğin Homebrew aracılığıyla) yüklediyseniz,
komutları ve seçenekleri otomatik olarak tamamlamak için Bash ve Zsh için kabuk
tamamlamaları yükleyebilirsiniz.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Global kurulum, kabuğunuzun `$PATH` ortam değişkeninde bulunan bir kurulumdur.
Bu, terminalinizdeki herhangi bir dizinden `tuist` komutunu çalıştırabileceğiniz
anlamına gelir. Bu, Homebrew için varsayılan kurulum yöntemidir.
<!-- -->
:::

#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/) yüklü ise, otomatik olarak yüklenen tamamlama
komut dosyalarının bulunduğu bir dizine zaten sahipsinizdir —
`.oh-my-zsh/completions`. Yeni tamamlama komut dosyanızı, bu dizinde `_tuist`
adlı yeni bir dosyaya kopyalayın:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` olmadan, tamamlama komut dosyaları için işlev yolunuza bir yol
eklemeniz ve tamamlama komut dosyasının otomatik yüklenmesini etkinleştirmeniz
gerekir. Öncelikle, şu satırları `~/.zshrc` dosyasına ekleyin:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Ardından, `~/.zsh/completion` adresinde bir dizin oluşturun ve tamamlama komut
dosyasını yeni dizine, yine `_tuist` adlı bir dosyaya kopyalayın.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion) yüklü ise, yeni
tamamlama komut dosyasını `/usr/local/etc/bash_completion.d/_tuist` dosyasına
kopyalayabilirsiniz:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Bash tamamlama özelliği yoksa, tamamlama komut dosyasını doğrudan kaynak olarak
kullanmanız gerekir. Komut dosyasını `~/.bash_completions/` gibi bir dizine
kopyalayın ve ardından `~/.bash_profile` veya `~/.bashrc` dosyasına aşağıdaki
satırı ekleyin:

```bash
source ~/.bash_completions/example.bash
```

#### Balık {#fish}

[fish shell](https://fishshell.com) kullanıyorsanız, yeni tamamlama komut
dosyasını `~/.config/fish/completions/tuist.fish` adresine kopyalayabilirsiniz:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
