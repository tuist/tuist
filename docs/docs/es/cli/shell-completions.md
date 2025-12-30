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
entorno `$PATH` de su shell. Esto significa que puedes ejecutar `tuist` desde
cualquier directorio de tu terminal. Este es el método de instalación por
defecto para Homebrew.
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

Sin `oh-my-zsh`, necesitará añadir una ruta para los scripts de finalización a
su ruta de funciones, y activar la autocarga de scripts de finalización.
Primero, añade estas líneas a `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

A continuación, cree un directorio en `~/.zsh/completion` y copie el script de
finalización en el nuevo directorio, de nuevo en un archivo llamado `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Si tienes [bash-completion](https://github.com/scop/bash-completion) instalado,
puedes simplemente copiar tu nuevo script de finalización al archivo
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Sin bash-completion, necesitarás obtener el script de finalización directamente.
Cópielo en un directorio como `~/.bash_completions/`, y luego añada la siguiente
línea a `~/.bash_profile` o `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Pescado {#fish}

Si utiliza [fish shell](https://fishshell.com), puede copiar su nuevo script de
finalización en `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
