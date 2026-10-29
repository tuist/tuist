---
{
  "title": "셸 자동 완성",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 명령어를 자동으로 완성하도록 셸을 구성하는 방법을 알아보세요."
}
---
# 셸 자동 완성

Tuist를 **전역으로 설치**했다면(예: Homebrew 사용), Bash와 Zsh에서 명령과 옵션을 자동으로 완성할 수 있는 셸 자동 완성을 설치할 수 있습니다.

> [!WARNING]
> **전역 설치가 무엇인가요**
>
> 전역 설치는 셸의 `$PATH` 환경 변수에서 사용할 수 있는 설치입니다. 즉, 터미널의 모든 디렉터리에서 `tuist`를 실행할 수 있습니다. 이는 Homebrew의 기본 설치 방법입니다.


#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/)가 설치되어 있다면, 자동 로드되는 자동 완성 스크립트 디렉터리인 `.oh-my-zsh/completions`가 이미 있습니다. 새로운 자동 완성 스크립트를 해당 디렉터리의 `_tuist`라는 새 파일로 복사하세요:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` 없이 사용하는 경우, 함수 경로에 자동 완성 스크립트 경로를 추가하고 자동 완성 스크립트 자동 로드를 활성화해야 합니다. 먼저 다음 줄을 `~/.zshrc`에 추가하세요:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

다음으로 `~/.zsh/completion`에 디렉터리를 생성하고 자동 완성 스크립트를 새 디렉터리로 복사하세요. 역시 `_tuist`라는 파일로 저장합니다.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion)이 설치되어 있다면, 새로운 자동 완성 스크립트를 `/usr/local/etc/bash_completion.d/_tuist` 파일로 복사하면 됩니다:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion이 없는 경우, 자동 완성 스크립트를 직접 소스해야 합니다. `~/.bash_completions/`와 같은 디렉터리에 복사한 후, 다음 줄을 `~/.bash_profile` 또는 `~/.bashrc`에 추가하세요:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

[fish shell](https://fishshell.com)을 사용하는 경우, 새로운 자동 완성 스크립트를 `~/.config/fish/completions/tuist.fish`로 복사할 수 있습니다:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
