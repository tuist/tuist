---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell tamamlamaları

Tuist **global olarak** yüklediyseniz (örneğin Homebrew aracılığıyla), komutları
ve seçenekleri otomatik olarak tamamlamak için Bash ve Zsh için kabuk
tamamlayıcıları yükleyebilirsiniz.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Genel kurulum, kabuğunuzun `$PATH` ortam değişkeninde bulunan bir kurulumdur.
Bu, terminalinizdeki herhangi bir dizinden `tuist` çalıştırabileceğiniz anlamına
gelir. Bu Homebrew için varsayılan kurulum yöntemidir.
<!-- -->
:::

#### Zsh {#zsh}

Eğer [oh-my-zsh](https://ohmyz.sh/) yüklüyse, otomatik olarak yüklenen tamamlama
betiklerinden oluşan bir dizine zaten sahipsinizdir - `.oh-my-zsh/completions`.
Yeni tamamlama betiğinizi bu dizindeki `_tuist` adlı yeni bir dosyaya
kopyalayın:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` olmadan, işlev yolunuza tamamlama betikleri için bir yol eklemeniz
ve tamamlama betiği otomatik yüklemesini açmanız gerekir. İlk olarak, bu
satırları `~/.zshrc` adresine ekleyin:

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

Eğer [bash-completion](https://github.com/scop/bash-completion) yüklüyse, yeni
tamamlama betiğinizi `/usr/local/etc/bash_completion.d/_tuist` dosyasına
kopyalayabilirsiniz:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion olmadan, tamamlama betiğini doğrudan kaynak olarak kullanmanız
gerekecektir. ` ~/.bash_completions/` gibi bir dizine kopyalayın ve ardından
aşağıdaki satırı `~/.bash_profile` veya `~/.bashrc` dizinine ekleyin:

```bash
source ~/.bash_completions/example.bash
```

#### Balık {#fish}

fish shell](https://fishshell.com) kullanıyorsanız, yeni tamamlama kodunuzu
`~/.config/fish/completions/tuist.fish` adresine kopyalayabilirsiniz:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
