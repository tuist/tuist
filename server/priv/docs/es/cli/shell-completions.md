---
{
  "title": "Completado de shell",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Aprende a configurar tu shell para autocompletar los comandos de Tuist."
}
---
# Completado de shell

Si tienes Tuist **instalado globalmente** (por ejemplo, mediante Homebrew), puedes instalar el completado de shell para Bash y Zsh para autocompletar comandos y opciones.

> [!WARNING]
> **Qué es una instalación global**
>
> Una instalación global es una instalación disponible en la variable de entorno `$PATH` de tu shell. Esto significa que puedes ejecutar `tuist` desde cualquier directorio en tu terminal. Este es el método de instalación predeterminado para Homebrew.


#### Zsh {#zsh}

Si tienes instalado [oh-my-zsh](https://ohmyz.sh/), ya dispones de un directorio con scripts de completado que se cargan automáticamente: `.oh-my-zsh/completions`. Copia tu nuevo script de completado a un archivo nuevo en ese directorio llamado `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Sin `oh-my-zsh`, tendrás que añadir una ruta para los scripts de completado a tu ruta de funciones y activar la carga automática de estos scripts. Primero, añade estas líneas a `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

A continuación, crea un directorio en `~/.zsh/completion` y copia el script de completado al nuevo directorio, nuevamente en un archivo llamado `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Si tienes instalado [bash-completion](https://github.com/scop/bash-completion), basta con copiar tu nuevo script de completado al archivo `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Sin bash-completion, tendrás que cargar el script de completado directamente. Cópialo a un directorio como `~/.bash_completions/` y luego añade la siguiente línea a `~/.bash_profile` o `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

Si usas [fish shell](https://fishshell.com), puedes copiar tu nuevo script de completado a `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
