---
{
  "title": "Build",
  "titleTemplate": ":title · Develop · Guides · Tuist",
  "description": "프로젝트를 효율적으로 빌드하기 위해 Tuist를 어떻게 사용하는지 배워봅니다."
}
---
# Build {#build}

프로젝트는 보통 빌드 시스템이 제공하는 CLI (예: `xcodebuild`) 를 통해 빌드됩니다. Tuist는 사용자 경험을 개선하고 최적화와 분석 기능을 제공하기 위해 이런 CLI를 래핑하여 플랫폼과 워크플로우를 통합합니다.

필요한 경우 `tuist generate`로 프로젝트를 생성하고 플랫폼별 CLI로 빌드 하는 것보다 `tuist build`를 사용하는 차이가 무엇인지 궁금할 수 있습니다. 다음은 그 차이에 대한 이유를 나타냅니다:

- **단일 명령어:** `tuist build`는 프로젝트 컴파일 전에 프로젝트를 생성합니다.
- **보기좋은 출력:** Tuist는 출력을 더 사용자 친화적으로 만들어 주는 [xcbeautify](https://github.com/cpisciotta/xcbeautify)와 같은 툴을 사용하여 출력합니다.
- <0><1>캐시:</1></0> 원격 캐시에서 빌드 artifact를 재사용하여 빌드를 최적화 합니다.
- **분석:** 다른 데이터 포인트와 연관된 지표를 수집하고 보고하여, 정보에 기반한 결정을 내릴 수 있게 도와줍니다.

## 사용법 {#usage}

`tuist build`는 필요하면 프로젝트를 생성한 다음에 플랫폼별 빌드 툴을 사용하여 빌드합니다. `--` 구분자를 사용하여 이후의 모든 인자를 직접 하위 빌드 툴로 전달하는 것을 지원합니다. 이것은 `tuist build`에서는 지원하지 않지만 하위 빌드 툴에서 지원하는 경우, 인자를 전달할 때 유용합니다.

::: code-group

```bash [Build a scheme]
tuist build MyScheme
```

```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```

```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```

:::
