---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# 쉘 자동 완성

**전역으로 설치된** Tuist를 가진 경우 (예: Homebrew를 통해), 명령과 옵션을 자동 완성하는 Bash 및 Zsh용 셸 완성
기능을 설치할 수 있습니다.

::: warning 전역 설치란?
<!-- -->
전역 설치는 쉘의 `$PATH` 환경 변수에서 사용할 수 있는 설치입니다. 즉, 터미널의 모든 디렉토리에서 `tuist`를 실행할 수 있습니다.
이것이 Homebrew의 기본 설치 방법입니다.
<!-- -->
:::

#### Zsh {#zsh}

oh-my-zsh](https://ohmyz.sh/)가 설치되어 있는 경우, 완성 스크립트를 자동으로 로드하는 디렉터리(
`.oh-my-zsh/completions`)가 이미 있습니다. 새 완성 스크립트를 해당 디렉토리의 새 파일 `_tuist` 에 복사하세요:

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

그런 다음, `~/.zsh/complication` 에 디렉터리를 만들고 완성 스크립트를 새 디렉터리에 복사한 다음, `_tuist` 라는
파일에 다시 복사합니다.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

bash-complement](https://github.com/scop/bash-completion)가 설치되어 있는 경우 새 완성 스크립트를
`/usr/local/etc/bash_complement.d/_tuist` 파일에 복사하기만 하면 됩니다:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion이 없으면 완성 스크립트를 직접 가져와야 합니다. ` ~/.bash_completions/` 와 같은 디렉터리에
복사한 다음 `~/.bash_profile` 또는 `~/.bashrc` 에 다음 줄을 추가합니다:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

[fish shell](https://fishshell.com)을 사용한다면, 새로운 완성 스크립트를
`~/.config/fish/completions/tuist.fish`에 복사하면 됩니다:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
