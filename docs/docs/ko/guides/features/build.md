---
{
  "title": "Build",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to build your projects efficiently."
}
---
# 빌드 {#빌드}

프로젝트는 일반적으로 빌드 시스템에서 제공하는 CLI(예: `xcodebuild`)를 통해 빌드됩니다. 튜이스트는 이를 래핑하여 사용자 경험을
개선하고 워크플로우를 플랫폼과 통합하여 최적화 및 분석을 제공합니다.

`tuist generate` (필요한 경우)로 프로젝트를 생성하고 플랫폼별 CLI로 빌드하는 것보다 `tuist build` 을 사용하는 것이
어떤 이점이 있는지 궁금할 수 있습니다. 몇 가지 이유가 있습니다:

- **단일 명령:** `tuist build` 프로젝트를 컴파일하기 전에 필요한 경우 프로젝트가 생성되도록 합니다.
- **미화된 출력:** 투이스트는 [xcbeautify](https://github.com/cpisciotta/xcbeautify)와 같은
  도구를 사용하여 출력을 더욱 사용자 친화적으로 만들어 줍니다.
- <LocalizedLink href="/guides/features/cache"><bold>Cache:</bold></LocalizedLink>
  원격 캐시에서 빌드 아티팩트를 결정론적으로 재사용하여 빌드를 최적화합니다.
- **애널리틱스:** 다른 데이터 포인트와 상관관계가 있는 메트릭을 수집하고 보고하여 정보에 입각한 의사 결정을 내릴 수 있도록 실행 가능한
  정보를 제공합니다.

## 사용량 {#사용량}

`tuist build` 는 필요한 경우 프로젝트를 생성한 다음 플랫폼별 빌드 도구를 사용하여 빌드합니다. ` --` 터미네이터를 사용하여 모든
후속 인수를 기본 빌드 도구로 직접 전달할 수 있습니다. 이는 `tuist build` 에서 지원되지 않지만 기본 빌드 도구에서 지원되는 인수를
전달해야 할 때 유용합니다.

::: 코드 그룹
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
