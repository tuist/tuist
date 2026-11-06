---
{
  "title": "셸 자동 완성",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 명령어를 자동으로 완성하도록 셸을 구성하는 방법을 알아보세요."
}
---
# 셸 자동 완성 {#shell-completions}

Tuist를 **전역 설치**했다면(예: Homebrew 사용), Zsh, Bash, Fish용 셸 자동 완성을 설치하여 명령어와 옵션을 자동으로 완성할 수 있습니다.

> [!NOTE]
> **전역 설치가 무엇인가요**
>
> 전역 설치란 셸의 `$PATH` 환경 변수에서 사용할 수 있는 설치 방식을 의미합니다. 즉, 터미널의 어떤 디렉터리에서도 `tuist`를 실행할 수 있습니다. 이는 Homebrew의 기본 설치 방법입니다.


## Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/)가 설치되어 있다면, 자동 로드되는 자동 완성 스크립트 디렉터리(`.oh-my-zsh/completions`)가 이미 존재합니다. 새로운 자동 완성 스크립트를 해당 디렉터리에 `_tuist`라는 이름의 새 파일로 복사하세요:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`가 없다면, 함수 경로에 자동 완성 스크립트 경로를 추가하고 자동 완성 스크립트 자동 로딩을 활성화해야 합니다. 먼저 다음 줄을 `~/.zshrc`에 추가하세요:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

다음으로 `~/.zsh/completion`에 디렉터리를 생성하고, 자동 완성 스크립트를 새 디렉터리에 다시 `_tuist`라는 파일로 복사하세요.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion)이 설치되어 있다면, 새로운 자동 완성 스크립트를 bash-completion 디렉터리에 복사하면 됩니다:

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion이 없다면, 자동 완성 스크립트를 직접 소스로 로드해야 합니다. `~/.bash_completions/`와 같은 디렉터리에 작성하세요:

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

그런 다음 다음 줄을 `~/.bash_profile` 또는 `~/.bashrc`에 추가하세요:

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

[fish shell](https://fishshell.com)을 사용한다면, 새로운 자동 완성 스크립트를 `~/.config/fish/completions/tuist.fish`에 복사할 수 있습니다:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
