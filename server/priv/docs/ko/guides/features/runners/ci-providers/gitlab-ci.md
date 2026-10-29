---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run GitLab CI jobs on Tuist Runners with machine selection through pipeline tags."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist Runners는 현재 초대 전용입니다. 계정에 대한 액세스를 요청하려면 [문의하세요](mailto:contact@tuist.dev).

파이프라인은 GitLab에 유지됩니다. Tuist는 각 작업에 대해 격리된 Linux 또는 macOS 머신을 제공하고, 해당 로그와 결과를 GitLab 및 Tuist 대시보드에 보고합니다. GitLab 19.3 이상 버전이 필요합니다. 공개 HTTPS로 접근 가능한 GitLab.com 및 자체 관리 인스턴스가 지원됩니다.

1. **GitLab 러너를 생성하세요.** 프로젝트의 **Settings → CI/CD → Runners**에서 프로젝트 러너를 생성하세요. 그룹 러너를 사용할 수도 있습니다. 러너 태그로 사용하려는 모든 Tuist 프로필 라벨(예: `tuist-linux`, `tuist-macos`)을 추가하고 **Run untagged jobs**를 비활성화하세요. GitLab이 표시하는 인증 토큰(`glrt-`으로 시작)을 보관하세요. 자체 머신에 러너를 설치할 필요는 없습니다.
2. **Tuist에서 한 번 연결하세요.** **Settings → Integrations**에서 GitLab CI 카드의 **Connect**를 선택하세요. GitLab URL과 러너 인증 토큰을 입력하세요. 이 연결은 다양한 프로필을 사용하는 작업을 처리할 수 있습니다. 토큰은 암호화되어 저장되며 다시 표시되지 않습니다. 선택적으로 API 액세스 토큰을 추가하여 병합 요청 파이프라인이 캐시 볼륨을 저장할 수 있도록 하세요. 자세한 내용은 [병합 요청 파이프라인](#merge-request-pipelines)을 참조하세요.
3. **각 작업에서 머신을 선택하세요.** 작업의 `tags`에 정확히 하나의 <.localized_link href="/guides/features/runners/profiles">Tuist 프로필 라벨</.localized_link>을 설정하세요. 등록된 GitLab 러너에도 동일한 태그가 있는 경우 다른 태그도 허용됩니다.

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **푸시하고 모니터링하세요.** Tuist는 1분 이내에 폴링을 시작합니다. 작업은 **Runners** 아래에 나타나며, GitLab 작업, 로그 및 머신 지표로 돌아가는 링크가 제공됩니다. GitLab은 작업 실행 중에 로그를 수신하고, Tuist는 작업 완료 시 마스킹된 로그를 수신합니다.

Tuist는 각 할당에서 `CI_JOB_TAGS`을 읽고 연결된 Tuist 계정 내에서 프로필을 해결합니다. `CI_RUNNER_TAGS`에서 머신을 추론하거나 기본 프로필을 사용하지 않습니다. Tuist 프로필 태그가 누락되었거나 알 수 없거나 여러 개인 경우, 획득한 작업이 실패하며 GitLab 로그에 설명이 표시됩니다. 파이프라인 변수에서 `CI_JOB_TAGS`을 재정의하지 마세요.

## 실행 환경 {#execution-environment}

작업은 격리된 머신 내부에서 GitLab의 **shell executor**를 사용합니다. 체크아웃, CI 변수, `before_script`, `script`, `after_script`, 아티팩트 및 취소는 GitLab Runner가 처리합니다. 파이프라인의 `image:` 및 `services:` 설정은 이 셸 환경을 구성하지 않습니다. <.localized_link href="/guides/features/runners/profiles">러너 이미지</.localized_link>에 설치된 도구를 사용하거나 스크립트에서 설치하세요.

재사용 가능한 러너 인증 토큰은 Tuist 서버에 유지됩니다. 머신은 할당된 작업에 대한 자격 증명만 수신합니다. 현재 GitLab 작업에는 캐시 서명 권한이 부여되지 않습니다. 맞춤형 Linux 캐시 볼륨은 GitLab의 API를 통해 작업 신원 및 저장 권한을 확인합니다. 재정의 가능한 CI 변수는 신뢰를 설정하지 않습니다.

Tuist가 작업을 획득하는 즉시 GitLab은 작업을 실행 중으로 표시하고 시간 제한을 시작합니다. Tuist가 이미 획득한 작업이 계정의 동시성 제한을 소모하는 동안 추가 작업은 GitLab에서 대기 상태가 됩니다. 획득한 작업은 최대 12시간까지 작업 시간 제한 동안 머신을 기다립니다. 그때까지 사용 가능한 머신이 없으면 Tuist는 `runner_system_failure`로 할당을 실패 처리하며, 위의 재시도 정책을 통해 GitLab이 이를 재시도할 수 있습니다. 동일한 정책은 러너 머신 손실 상황에도 적용됩니다.

## 토큰 교체 및 연결 해제 {#rotating-tokens-and-disconnecting}

연결의 토큰을 업데이트하고 **Save changes**를 선택하여 교체하세요. 토큰을 빈 상태로 두면 기존 자격 증명이 유지됩니다.

**Disconnect**는 획득을 중지하고 대기 중인 할당을 실패 처리합니다. 실행 중인 작업은 자체 자격 증명으로 계속됩니다. GitLab에 도달할 수 없는 경우, Tuist는 대기 중인 할당 취소를 재시도하면서 비활성화된 연결을 유지합니다. 해당 할당이 해결되면 연결이 제거됩니다.

## 캐시 볼륨 {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>을 사용하여 작업 간에 Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 유지하세요. 체크아웃 후와 이를 사용하는 명령 전에 추가하세요.

### 병합 요청 파이프라인 {#merge-request-pipelines}

프로젝트의 푸시, 일정 및 웹 파이프라인은 변경 사항을 캐시 볼륨에 저장합니다. 병합 요청 파이프라인은 캐시를 사용하며, 연결에 API 액세스 토큰이 있는 경우에만 변경 사항을 저장합니다.

1. GitLab에서 **Reporter** 역할과 `read_api` 범위를 가진 프로젝트 또는 그룹 액세스 토큰을 생성하세요. 그룹 토큰은 Tuist 러너에서 실행되는 그룹 내 모든 프로젝트를 포함합니다.
2. **Settings → Integrations**에서 GitLab CI 카드의 **API access token**에 붙여넣고 **Save changes**를 선택하세요.

Tuist는 각 병합 요청 파이프라인의 병합 요청을 읽습니다. 프로젝트 자체의 브랜치에서 열린 병합 요청의 파이프라인은 변경 사항을 병합 요청의 소스 브랜치 아래에 저장하므로, 러너 프로필의 <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">브랜치 설정</.localized_link>이 해당 브랜치에 적용됩니다. 포크에서의 병합 요청은 절대 저장되지 않습니다. Tuist가 병합 요청을 읽을 수 없는 경우에도 작업은 실행되고 캐시를 사용하지만 변경 사항은 삭제됩니다.
