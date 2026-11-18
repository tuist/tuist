---
{
  "title": "Once 원격 실행",
  "titleTemplate": ":title · Runners · 기능 · 가이드 · Tuist",
  "description": "적합한 Once 그래프 명령 작업을 Tuist의 Linux 원격 실행 워커에서 실행합니다."
}
---
# Once 원격 실행 {#once-remote-execution}

공유 캐싱은 다른 머신이 이미 완료한 작업을 반복하지 않도록 합니다. 원격 실행은 자격 있는 캐시 미스를 컴퓨터에서 외부로 이동합니다. Once는 Tuist의 일회용 Linux 워커에서 그래프 명령 액션을 스케줄링하고, 동일한 프로젝트 캐시를 통해 출력을 가져옵니다.

> [!IMPORTANT]
> **요구 사항**
>
> - 원격 실행이 활성화되고 사용 가능한 실행 용량이 있는 Tuist 계정.
> - Tuist 원격 실행을 지원하는 Once 버전.
> - 워커 이미지, 캐시 엔드포인트, 동시성 및 절대 실행 디렉터리를 광고하는 호환 서버. 디렉터리를 생략하는 서버는 현재 Once 클라이언트와 호환되지 않으며, Once는 작업 업로드 전에 중단됩니다.
> - 광고된 워커 이미지 내에서 `linux/amd64`에서 실행할 수 있는 명령어와 툴체인.

이는 전체 CI 작업이 아닌 그래프 액션을 실행합니다. Once를 구성한다고 해서 GitHub 또는 GitLab 워크플로우 오케스트레이션이 설치되는 것은 아닙니다.

## 설정 {#setup}

<.localized_link href="/guides/get-started/once-project">Once 시작하기</.localized_link>를 완료하세요. 캐싱과 실행에 동일한 Tuist 제공자를 선택하고, 서비스에서 광고하는 워커 이미지를 고정하세요:

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

프로젝트 캐시를 읽고 쓸 수 있는 자격 증명으로 인증한 후, 원격 실행을 요청하세요:

```bash
once build --remote MyTarget
```

타겟과 이미지 태그를 자신의 것으로 교체하세요. Once는 작업을 업로드하기 전에 광고된 이미지, 실행 디렉터리, 캐시 대상 및 계정 용량을 확인합니다. 캐시와 실행은 동일한 프로젝트를 참조해야 합니다.

## 워커용 액션 준비 {#prepare-actions-for-workers}

- 입력과 출력을 선언하세요. 출력은 액션의 작업 디렉터리 하위에 있어야 합니다.
- 도구는 시작 컴퓨터의 절대 경로가 아닌 워커 이미지 내에서 해결하세요.
- 반복해도 안전한 액션을 사용하세요. 워커 장애나 서비스 재시작으로 인해 다른 실행이 발생할 수 있습니다.
- 타임아웃을 서비스의 10분 액션 제한 내에 유지하세요. 네트워크 차단 등 지원되지 않는 요구 사항은 로컬에서 암묵적으로 실행되는 대신 실패합니다.

Once는 계정의 광고된 액션 동시성을 준수하며, 서비스 큐가 가득 차면 백오프합니다. 이미지를 변경하면 빌드 구성과 캐시된 결과가 분리되어 호환되지 않는 워커 이미지 간 재사용이 방지됩니다.

큐잉, 인증 갱신 및 캐시 엔드포인트 재정의에 대해서는 [Once의 원격 실행 가이드](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)를 참조하세요. 결과 실행을 검사하려면 <.localized_link href="/guides/features/build-insights/once">Once 빌드 인사이트</.localized_link>를 따르세요.
