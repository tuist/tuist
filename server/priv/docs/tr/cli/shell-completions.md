---
{
  "title": "Kabuk tamamlamaları",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist komutlarını otomatik tamamlamak için kabuğunuzu nasıl yapılandıracağınızı öğrenin."
}
---
# Kabuk tamamlamaları {#shell-completions}

Tuist'i **genel olarak kurduysanız** (örneğin Homebrew aracılığıyla), Zsh, Bash ve Fish için kabuk tamamlamalarını yükleyerek komutları ve seçenekleri otomatik tamamlayabilirsiniz.

> [!NOTE]
> **Genel kurulum nedir**
>
> Genel kurulum, kabuğunuzun `$PATH` ortam değişkeninde bulunan bir kurulumdur. Bu, terminalinizde herhangi bir dizinden `tuist` çalıştırabileceğiniz anlamına gelir. Bu, Homebrew için varsayılan kurulum yöntemidir.


## Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/) yüklüyse, otomatik olarak yüklenen tamamlama betiklerinin bulunduğu bir dizine zaten sahipsiniz — `.oh-my-zsh/completions`. Yeni tamamlama betiğinizi o dizindeki `_tuist` adlı yeni bir dosyaya kopyalayın:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` olmadan, tamamlama betikleri için bir yolu işlev yolunuza eklemeniz ve tamamlama betiği otomatik yüklemeyi etkinleştirmeniz gerekir. İlk olarak, şu satırları `~/.zshrc` dosyasına ekleyin:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Ardından, `~/.zsh/completion` konumunda bir dizin oluşturun ve tamamlama betiğini yine `_tuist` adlı bir dosyaya kopyalayarak yeni dizine taşıyın.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion) yüklüyse, yeni tamamlama betiğinizi doğrudan bash-completion'ın dizinine kopyalayabilirsiniz:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion olmadan, tamamlama betiğini doğrudan kaynak olarak yüklemeniz gerekir. Betiği `~/.bash_completions/` gibi bir dizine yazın:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

Ardından aşağıdaki satırı `~/.bash_profile` veya `~/.bashrc` dosyasına ekleyin:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

[fish shell](https://fishshell.com) kullanıyorsanız, yeni tamamlama betiğinizi `~/.config/fish/completions/tuist.fish` konumuna kopyalayabilirsiniz:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
