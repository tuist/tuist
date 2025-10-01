---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Se tem o Tuist **globalmente instalado** (e.g., via Homebrew), pode instalar
complementos de shell para o Bash e Zsh para autocompletar comandos e opções.

::: aviso O QUE É UMA INSTALAÇÃO GLOBAL Uma instalação global é uma instalação
que está disponível na variável de ambiente `$PATH` da sua shell. Isto significa
que pode correr `tuist` a partir de qualquer diretório no seu terminal. Este é o
método de instalação predefinido para o Homebrew. :::

#### Zsh {#zsh}

Se tiver o [oh-my-zsh](https://ohmyz.sh/) instalado, já tem um diretório de
scripts de conclusão de carregamento automático - `.oh-my-zsh/completions`.
Copie o seu novo script de conclusão para um novo ficheiro nesse diretório
chamado `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Sem `oh-my-zsh`, terá de adicionar um caminho para scripts de conclusão ao seu
caminho de funções, e ativar o carregamento automático de scripts de conclusão.
Primeiro, adicione estas linhas a `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Em seguida, crie um diretório em `~/.zsh/completion` e copie o script de
conclusão para o novo diretório, novamente para um ficheiro chamado `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Se tiver o [bash-completion](https://github.com/scop/bash-completion) instalado,
pode simplesmente copiar o seu novo script de conclusão para o ficheiro
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Sem o bash-completion, terá de obter o script de conclusão diretamente. Copie-o
para um diretório tal como `~/.bash_completions/`, e depois adicione a seguinte
linha a `~/.bash_profile` ou `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Peixe

Se usar [fish shell](https://fishshell.com), pode copiar o seu novo script de
conclusão para `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
