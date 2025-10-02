---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Tuist **** 를 전역적으로 설치한 경우(예: 홈브류를 통해) Bash 및 Zsh용 셸 완성 기능을 설치하여 명령 및 옵션을 자동 완성할
수 있습니다.

::: 경고 글로벌 설치란 무엇인가 글로벌 설치는 셸의 `$PATH` 환경 변수에서 사용할 수 있는 설치입니다. 즉, 터미널의 모든 디렉토리에서
`tuist` 을 실행할 수 있습니다. 이것은 Homebrew의 기본 설치 방법입니다.:::

#### Zsh {#zsh}

oh-my-zsh](https://ohmyz.sh/)가 설치되어 있는 경우 완성 스크립트를 자동으로 로드하는 디렉터리(
`.oh-my-zsh/completions`)가 이미 있습니다. 새 완성 스크립트를 해당 디렉토리의 새 파일 `_tuist` 에 복사합니다:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` 이 없으면 함수 경로에 완성 스크립트 경로를 추가하고 완성 스크립트 자동 로딩을 사용 설정해야 합니다. 먼저
`~/.zshrc` 에 다음 줄을 추가합니다:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

그런 다음 `~/.zsh/complication` 에 디렉터리를 만들고 완성 스크립트를 새 디렉터리에 복사한 다음 `_tuist` 라는 파일에
다시 복사합니다.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

bash-complement](https://github.com/scop/bash-completion)가 설치되어 있는 경우 새 완료 스크립트를
`/usr/local/etc/bash_complement.d/_tuist` 파일에 복사하기만 하면 됩니다:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion이 없으면 완성 스크립트를 직접 소싱해야 합니다. ` ~/.bash_completions/` 와 같은 디렉터리에
복사한 다음 `~/.bash_profile` 또는 `~/.bashrc` 에 다음 줄을 추가합니다:

```bash
source ~/.bash_completions/example.bash
```

#### 물고기 {#fish}

물고기 껍질](https://fishshell.com)을 사용하는 경우, 새 완성 스크립트를
`~/.config/fish/complements/tuist.fish` 에 복사할 수 있습니다:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
