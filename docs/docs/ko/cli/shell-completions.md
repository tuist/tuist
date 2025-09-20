---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 명령어를 자동으로 완성하도록 셀을 구성하는 방법에 대해 배워봅니다."
}
---
# Shell completions

Tuist가 **전역으로 설치된 경우** (예: Homebrew),
명령어와 옵션을 자동으로 완성시키기 위해 Bash와 Zsh용 셀 자동 완성을 설치할 수 있습니다.

:::warning WHAT IS A GLOBAL INSTALLATION
Global installation는 Shell의 `$PATH` 환경 변수에 포함된 설치를 말합니다. 즉, 터미널의 모든 디렉토리에서 `tuist`를 실행할 수 있습니다.이것은 Homebrew의 기본 설치 방법입니다. 이것은 Homebrew의 기본 설치 방법입니다.
:::

#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh)가 설치되어 있다면, 이미 자동으로 로드되는 완성 스크립트(completion script)들이 저장된 디렉터리인 `.oh-my-zsh/completions`가 있습니다. 새로운 완성 스크립트를 해당 디렉터리의 `_tuist`라는 새 파일에 복사합니다.

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`가 없는 경우 함수 경로에 완성 스크립트 경로를 추가하고, 완성 스크립트 자동 로딩을 설정해야 합니다. 먼저 `~/.zshrc`에 다음 줄을 추가합니다

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

그런 다음, `~/.zsh/complication`에 디렉터리를 생성한 후, 완성 스크립트를 해당 디렉터리의 `_tuist`라는 파일에 복사합니다.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

bash-complement](https://github.com/scop/bash-completion)가 설치되어 있다면, 새로운 완성 스크립트를 `/usr/local/etc/bash_complement.d/_tuist` 파일에 복사하기만 하면 됩니다.

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion이 없으면 완성 스크립트를 직접 불러와야 합니다. 해당 스크립트를 `~/.bash_completions/`와 같은 디렉터리로 복사한 다음 `~/.bash_profile` 또는 `~/.bashrc`에 다음 줄을 추가합니다.

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

[fish shell](https://fishshell.com)을 사용하는 경우 `~/.config/fish/completions/tuist.fish`에 새로운 자동완성 스크립트를 복사할 수 있습니다:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
