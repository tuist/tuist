---
{
  "title": "Completado de shell",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Aprende a configurar tu shell para autocompletar los comandos de Tuist."
}
---
# Completado de shell {#shell-completions}

Si tienes Tuist **instalado globalmente** (por ejemplo, a través de Homebrew), puedes instalar el completado de shell para Zsh, Bash y Fish para autocompletar comandos y opciones.

> [!NOTE]
> **¿Qué es una instalación global?**
>
> Una instalación global es una instalación que está disponible en la variable de entorno `$PATH` de tu shell. Esto significa que puedes ejecutar `tuist` desde cualquier directorio en tu terminal. Este es el método de instalación predeterminado para Homebrew.


## Zsh {#zsh}

Si tienes instalado [oh-my-zsh](https://ohmyz.sh/), ya dispones de un directorio de scripts de completado que se cargan automáticamente: `.oh-my-zsh/completions`. Copia tu nuevo script de completado a un archivo nuevo en ese directorio llamado `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Sin `oh-my-zsh`, tendrás que añadir una ruta para los scripts de completado a tu ruta de funciones y activar la carga automática de los scripts de completado. Primero, añade estas líneas a `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

A continuación, crea un directorio en `~/.zsh/completion` y copia el script de completado al nuevo directorio, nuevamente en un archivo llamado `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

Si tienes instalado [bash-completion](https://github.com/scop/bash-completion), simplemente puedes copiar tu nuevo script de completado al directorio de bash-completion:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

Sin bash-completion, tendrás que cargar el script de completado directamente. Escríbelo en un directorio como `~/.bash_completions/`:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

Luego añade la siguiente línea a `~/.bash_profile` o `~/.bashrc`:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

Si usas [fish shell](https://fishshell.com), puedes copiar tu nuevo script de completado a `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
