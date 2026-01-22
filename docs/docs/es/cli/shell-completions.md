---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Auto-completado en shells

Si tienes Tuist **instalado globalmente** (por ejemplo, a través de Homebrew),
puedes instalar completions de shell para Bash y Zsh para autocompletar comandos
y opciones.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Una instalación global es una instalación que está disponible en la variable de
entorno $PATH` de su shell `. Esto significa que puede ejecutar `tuist` desde
cualquier directorio de su terminal. Este es el método de instalación
predeterminado para Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

Si tiene [oh-my-zsh](https://ohmyz.sh/) instalado, ya tiene un directorio de
scripts para cargar scripts de autocompletado automáticamente -
`.oh-my-zsh/completions`. Copie su nuevo script de finalización a un nuevo
archivo en ese directorio llamado `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Sin `oh-my-zsh`, tendrás que añadir una ruta para los scripts de autocompletado
a tu ruta de funciones y activar la carga automática de scripts de
autocompletado. En primer lugar, añade estas líneas a `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

A continuación, crea un directorio en `~/.zsh/completion` y copia el script de
completado al nuevo directorio, de nuevo en un archivo llamado `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Si tienes instalado [bash-completion](https://github.com/scop/bash-completion),
solo tienes que copiar tu nuevo script de autocompletado al archivo
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Sin la función de autocompletado de bash, tendrás que ejecutar el script de
autocompletado directamente. Cópialo en un directorio como
`~/.bash_completions/` y, a continuación, añade la siguiente línea a
`~/.bash_profile` o `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Pescado {#fish}

Si utilizas [fish shell](https://fishshell.com), puedes copiar tu nuevo script
de autocompletado a `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
