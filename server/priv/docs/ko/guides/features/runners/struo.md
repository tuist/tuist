---
{
  "title": "Struo 원격 실행",
  "titleTemplate": ":title · Runners · 기능 · 가이드 · Tuist",
  "description": "적합한 Struo 그래프 명령 작업을 Tuist의 Linux 원격 실행 워커에서 실행합니다."
}
---
# Struo 원격 실행 {#struo-remote-execution}

<a id="once-remote-execution"></a>

공유 캐싱은 다른 머신이 이미 완료한 작업을 반복하지 않도록 합니다. 원격 실행은 자격을 갖춘 캐시 미스를 여러분의 컴퓨터에서 벗어나게 합니다. Struo는 Tuist의 일회용 Linux 워커에서 그래프 명령 액션을 스케줄링하고 동일한 프로젝트 캐시를 통해 출력을 가져옵니다.

> [!NOTE]
> 원격 실행은 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의하세요](mailto:contact@tuist.dev).

> [!IMPORTANT]
> **요구 사항**
>
> - 원격 실행이 활성화되고 사용 가능한 실행 용량이 있는 Tuist 계정.
> - Tuist 원격 실행을 지원하는 Struo 버전.
> - 워커 이미지, 캐시 엔드포인트, 동시성 및 절대 실행 디렉터리를 광고하는 호환 서버. 디렉터리를 생략하는 서버는 현재 Struo 클라이언트와 호환되지 않으며, Struo는 작업 업로드 전에 중단됩니다.
> - 광고된 워커 이미지 내에서 `linux/amd64`에서 실행할 수 있는 명령어와 툴체인.

이는 전체 CI 작업이 아닌 그래프 액션을 실행합니다. Struo를 구성한다고 해서 GitHub 또는 GitLab 워크플로 오케스트레이션이 설치되는 것은 아닙니다.

## 설정 {#setup}

<.localized_link href="/guides/get-started/struo-project">Struo 시작하기</.localized_link>를 완료하세요. 캐싱과 실행에 대해 동일한 Tuist 제공자를 선택하고 서비스에서 광고하는 워커 이미지를 고정하세요:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

프로젝트 캐시를 읽고 쓸 수 있는 자격 증명으로 인증한 후 원격 실행을 요청하세요:

```bash
struo build --remote MyTarget
```

타겟과 이미지 태그를 자신의 것으로 바꾸세요. Struo는 작업을 업로드하기 전에 광고된 이미지, 실행 디렉터리, 캐시 대상 및 계정 용량을 확인합니다. 캐시와 실행은 동일한 프로젝트를 참조해야 합니다.

## 워커용 액션 준비 {#prepare-actions-for-workers}

- 입력과 출력을 선언하세요. 출력은 액션의 작업 디렉터리 아래에 있어야 합니다.
- 도구를 시작 컴퓨터의 절대 경로가 아닌 워커 이미지 내에서 해결하세요.
- 반복해도 안전한 액션을 사용하세요. 워커 장애나 서비스 재시작으로 인해 다른 실행이 발생할 수 있습니다.
- 타임아웃을 서비스의 10분 액션 제한 이내로 유지하세요. 네트워크 차단 등 지원되지 않는 요구 사항은 로컬에서 자동으로 실행되지 않고 실패합니다.

Struo는 계정의 광고된 액션 동시성을 준수하며 서비스 큐가 가득 차면 백오프합니다. 이미지를 변경하면 빌드 구성과 캐시된 결과가 분리되어 호환되지 않는 워커 이미지 간 재사용이 방지됩니다.

## 원격 실행 검사 {#inspect-remote-execution}

프로젝트 사이드바에는 **원격 실행** 페이지가 있습니다. **분석** 카드에는 선택한 기간의 실행 횟수와 총 실행 시간이 표시되며, 이는 <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">액션 실행 및 사용량</.localized_link>에서 설명한 대로입니다. Struo 2.19.0 이후 릴리스에서는 각 원격 액션이 속한 Struo 실행 이름을 지정하므로, 이 페이지는 대기 시간과 실행 시간을 차트로 표시하고 실행 중인 실행을 먼저 나열하여 원격 액션, 결과 및 타이밍과 함께 실행을 목록으로 보여줍니다. 실행을 클릭하면 **빌드 실행**에서 해당 페이지가 열립니다. 이전 클라이언트의 실행과 원격 캐시에서 응답된 액션은 여기에 포함되지 않습니다. 현재 실행 중이거나 대기 중인 원격 액션은 `get_remote_execution_activity` MCP 도구와 해당 REST 엔드포인트에서 확인할 수 있습니다. 둘 다 워커 레인이 아닌 실행 서비스에서 제공됩니다.

큐잉, 인증 갱신 및 캐시 엔드포인트 재정의에 대해서는 [Struo의 원격 실행 가이드](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)를 참조하세요. 결과 실행을 검사하려면 <.localized_link href="/guides/features/build-insights/struo">Struo 빌드 인사이트</.localized_link>를 따르세요.
