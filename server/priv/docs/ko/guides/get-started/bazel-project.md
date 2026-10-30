---
{
  "title": "Bazel 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "BUILD 파일을 변경하지 않고 Bazel 워크스페이스를 Tuist에 연결하여 CI 전반에서 공유 원격 캐시와 빌드 및 테스트 인사이트를 활용하세요."
}
---
# Bazel 프로젝트 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

기존 Bazel 워크스페이스를 Tuist에 연결하려면 이 경로를 따르세요. Tuist는 Bazel이 원격 캐시로 연결하는 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 캐시와, 모든 빌드 및 테스트 결과를 대시보드에서 볼 수 있는 데이터로 변환하는 Build Event Service 스트림을 제공합니다.

아래 각 섹션은 현재 부족한 부분을 먼저 설명한 다음, 그 격차를 채워주는 기능을 안내합니다.

## 필수 조건

- Bazel 워크스페이스(루트에 `WORKSPACE` 또는 `MODULE.bazel`가 있음)와 `PATH`에 포함된 Bazel.
- <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스</.localized_link>.

## 워크스페이스 연결

> [!NOTE]
> `tuist init` 내부의 Bazel 워크플로는 해당 버전과 함께 제공되는 Tuist CLI 버전을 필요로 합니다. 이전 릴리스에서는 `tuist init`가 "Integrate a Bazel workspace" 옵션을 표시하지 않습니다. 대신 워크스페이스 루트에서 `tuist auth login`를 실행한 후 `tuist bazel setup`를 실행하여 아래 단계와 동일한 과정을 진행하세요.

Bazel 워크스페이스의 루트에서 `tuist init`를 실행하세요. Tuist는 `WORKSPACE` / `MODULE.bazel`를 감지하고 **Bazel 워크스페이스 통합** 옵션을 제공합니다. 브라우저에서 인증하고 프로젝트를 소유할 계정을 선택하세요.

```bash
tuist init
```

코딩 에이전트나 스크립트로 이 작업을 수행하는 경우, 먼저 `tuist auth login`를 실행하세요(브라우저 흐름에서 Enter 키를 누를 때까지 대기). 그다음 비대화형 형식을 사용하세요:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init이 완료되면 Tuist는 다음과 같이 동작합니다:

1. 프로젝트 핸들이 포함된 `tuist.toml`를 워크스페이스 루트에 작성합니다.
2. `.bazelrc` 옆에 `.bazelrc.tuist`를 작성하며, 가장 가까운 Tuist 캐시 리전에 연결되고 워크스페이스별 자격 증명 헬퍼를 통해 인증됩니다.
3. `.bazelrc`에 `try-import %workspace%/.bazelrc.tuist` 줄을 추가합니다.

`try-import` 줄을 커밋하세요. 모든 머신에서 동일합니다. `.gitignore`에 `.bazelrc.tuist`를 추가하세요. 자격 증명 헬퍼 경로는 사용자별이며 캐시 리전은 위치별이므로 공유해서는 안 됩니다.

워크스페이스가 연결되면 아래 모든 기능이 자동으로 활성화됩니다.

## 원격 캐시

Bazel의 자체 로컬 디스크 캐시는 `~/.cache/bazel` 아래(또는 `--disk_cache`가 지정한 위치)에 저장됩니다. 한 개발자의 머신에서 발생한 캐시 히트는 다른 사람에게 전달되지 않으며, CI 작업 컨테이너는 매 실행마다 빈 캐시에서 시작합니다.

Bazel의 [Remote Execution API](https://github.com/bazelbuild/remote-apis)는 동일한 캐시를 공유 엔드포인트로 확장하기 위한 프로토콜입니다. Tuist는 이 프로토콜을 지원합니다. `.bazelrc.tuist`가 준비되면 Bazel은 출력이 이미 공유 캐시에 있는 액션을 건너뛰고 대신 다운로드합니다. 한 머신의 작업은 동일한 리비전을 빌드하는 다른 모든 머신에 도움이 됩니다.

동일한 리비전 against 두 개의 클린 빌드로 확인하세요(로컬에서, 또는 로컬 하나 + CI 하나):

```bash
bazel clean
bazel build //...
```

두 번째 실행 요약에서 캐시 히트가 보고되어야 합니다. 대시보드에서 **캐시**를 열어 시간 경과에 따른 히트율을 확인하세요.

## 빌드 및 테스트 인사이트

Bazel의 빌드 이벤트 스트림과 테스트별 XML 보고서는 호출마다 생성됩니다. 일주일 동안 타겟 수준의 지속 시간을 비교하거나 여러 CI 실행에서 불안정해진 테스트를 발견하려면 이러한 이벤트를 수집하고 집계해야 합니다.

Bazel이 이미 내보내는 Build Event Service 프로토콜은 바로 이를 위해 설계되었습니다. `tuist init`가 작성한 `.bazelrc.tuist`는 BES 스트림을 Tuist에 맞게 구성하므로, 다음 `bazel build` 및 `bazel test`부터 빌드 및 테스트 인사이트가 흐르기 시작합니다. 추가 구성이 필요하지 않습니다. 대시보드에서 **빌드** 및 **테스트**를 열어 데이터를 확인하세요.

## 팀 참여 유도

캐시 히트와 인사이트는 프로젝트에 연결된 인원 수에 따라 누적됩니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩을 개인별 `tuist auth login` 대신 클릭 한 번으로 완료할 수 있게 하세요.
