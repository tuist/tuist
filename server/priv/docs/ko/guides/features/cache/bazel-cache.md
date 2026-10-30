---
{
  "title": "Bazel 캐시",
  "titleTemplate": ":title · 캐시 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 팀과 CI 간에 Bazel 원격 캐시 항목을 공유하세요."
}
---
# Bazel 캐시 {#bazel-cache}

Tuist는 Bazel이 원격 캐시로 연결하는 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 캐시를 제공합니다. 액션의 출력이 이미 캐시에 있으면 Bazel은 해당 액션을 건너뛰고 Tuist의 캐시에서 결과를 가져와 팀과 CI 환경 전체의 컴파일 시간을 절약합니다.

## 설정 {#setup}

Bazel 워크스페이스 루트에서 다음을 실행하세요:

```bash
tuist bazel setup
```

이 명령은 가장 가까운 Tuist 캐시 리전에 연결되고 워크스페이스별 자격 증명 도우미를 통해 인증되는 `.bazelrc.tuist` 파일을 `.bazelrc` 옆에 생성합니다. 또한 저장소의 `.bazelrc`에 `try-import` 줄을 추가합니다:

```text
try-import %workspace%/.bazelrc.tuist
```

가져오기를 직접 관리하려면 `--no-add-bazelrc-import`를 전달하세요.

`.bazelrc.tuist`를 `.gitignore`에 추가하고 커밋하지 않고 각 머신에서 설정을 실행하세요. 생성된 파일은 현재 사용자의 Tuist 구성 디렉터리 아래 절대 자격 증명 도우미 경로와 해당 파일을 생성한 머신과 가장 가까운 캐시 리전을 가리키므로 두 값 모두 동료나 지속적 통합 러너로 전달되지 않습니다. 모든 머신에서 동일한 `.bazelrc`의 `try-import` 줄을 커밋하세요.

설정은 Bazel 워크스페이스 마커를 찾을 수 없거나, 파일이 심볼릭 링크이거나, 이미 원격 캐시 또는 Build Event Service를 구성한 경우 기존 `.bazelrc`를 그대로 둡니다. 따라서 다시 실행해도 멱등성이 유지됩니다.

통합을 확인하려면 일반 Bazel 명령을 실행하세요:

```bash
bazel build //...
```

캐시 활동은 Tuist 대시보드의 프로젝트 **Bazel Cache** 페이지에 표시되며, 여기에는 캐시 전송, 다운로드 및 업로드, 읽기 및 쓰기 지연 시간, 처리량, 액션 캐시 히트율이 나타납니다. 프로젝트 **Overview**에는 빌드 기간과 함께 동일한 액션 캐시 히트율 요약이 제공됩니다.

명령이 캐시를 어떻게 사용했는지 확인하려면 **Invocations**에서 열어보세요. 호출 페이지는 액션 캐시 조회와 콘텐츠 객체 요청을 분리하여 표시하므로 콜드 액션 캐시와 느린 아티팩트 다운로드를 구분할 수 있습니다.

## 빌드 인사이트 {#build-insights}

기본적으로 `tuist bazel setup`는 Bazel의 Build Event Service도 구성하므로 완료된 명령이 **Invocations** 대시보드에 표시됩니다. 대시보드에 표시되는 내용과 사용자 정의 메타데이터를 첨부하는 방법은 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>를 참조하세요.

원격 캐시만 사용하고 빌드 이벤트 스트림을 보내지 않으려면 다음 옵션을 사용하세요:

```bash
tuist bazel setup --no-build-insights
```

## 지속적 통합 {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>의 방법 중 하나로 CI를 인증한 후, 체크아웃 단계의 일부로 `tuist bazel setup`를 한 번 실행하여 `.bazelrc.tuist`가 러너에 적합한 리전을 반영하도록 하세요. 제공업체별 예제는 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>를 참조하세요.

## 데이터 보존 {#data-retention}

Tuist는 원격 캐시 관찰 데이터를 90일 동안 보관합니다. 전체 정책은 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>을 참조하세요.
