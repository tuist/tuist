---
{
  "title": "Xcode 빌드 인사이트",
  "titleTemplate": ":title · 빌드 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Xcode 빌드 분석을 추적하여 로컬 및 CI 빌드 성능을 모니터링하세요."
}
---
# Xcode 빌드 인사이트 {#xcode-build-insights}

대규모 프로젝트 작업에서 동일한 코드를 반복해서 다시 빌드할 필요는 없습니다. Tuist Build Insights를 사용하면 로컬 및 CI 빌드 시간이 병목 현상이 되기 전에 추세를 파악할 수 있도록 빌드 분석을 추적할 수 있습니다.

빌드 인사이트는 일반적으로 스킴의 사후 액션(post-action)에 추가되는 `tuist inspect build` 명령어로 구동됩니다.

로컬 빌드 시간 추적을 시작하려면 스킴의 사후 액션(post-action)에 `tuist inspect build` 명령어를 추가하여 활용할 수 있습니다:

![빌드 검사용 사후 액션](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> "Provide build settings from" 필드를 실행 파일이나 주요 빌드 대상으로 설정하여 빌드 구성을 캡처하세요.

> [!NOTE]
> 빌드가 실패하면 사후 스킴 액션은 실행되지 않습니다.
>
> 이 경우 스킴의 `.xcscheme` 파일 내 `<BuildAction>` 요소에서 `runPostActionsOnFailure`를 `YES`로 설정하여 실행할 수 있습니다:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/)의 경우, 사후 액션 환경에서 `tuist`를 활성화하세요:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 경로 해결**
>
> 환경의 `PATH`는 스킴 사후 액션으로 상속되지 않으므로 Mise의 절대 경로를 사용하세요. 이는 Mise 설치 방법에 따라 달라집니다. 빌드 설정은 대상에서 상속되어야 하므로 `mise`가 `$SRCROOT`에서 실행될 수 있습니다.

[Homebrew](https://brew.sh/)의 경우, Homebrew 경로를 사후 액션 환경에 추가하세요:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

로그인하면 로컬 빌드가 추적되어 Tuist 대시보드에서 확인할 수 있습니다:

> [!TIP]
> 대시보드에 빠르게 접근하려면 CLI에서 `tuist project show --web`를 실행하세요.

![빌드 인사이트가 포함된 대시보드](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
