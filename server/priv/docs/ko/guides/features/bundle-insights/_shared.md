## 태그 {#tags}

빌드 변형, 환경 또는 릴리스 채널을 구분하기 위해 번들을 업로드할 때 태그를 첨부하세요. 번들 태그는 빌드 인사이트 태그와 동일한 규칙을 따릅니다:

```bash
tuist inspect bundle App.ipa --tags paid production
```

CI에서는 `TUIST_BUNDLE_TAGS`를 사용하여 쉼표로 구분된 태그를 설정할 수도 있습니다:

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

명시적 `--tags`는 환경 변수의 태그를 대체합니다. 태그에는 문자, 숫자, 하이픈 및 밑줄을 사용할 수 있으며, 번당 최대 10개의 태그와 태그당 최대 50자를 허용합니다. 동일한 옵션은 Android 번들에도 적용됩니다. `--json`는 로컬에서만 작동하며 태그나 번들을 업로드하지 않습니다.

태그는 번들 이름 옆과 번들 세부 정보에 표시됩니다. 대시보드의 **태그** 필터를 사용하고 태그를 입력하여 번들 목록에 포함하거나 제외하세요. 필터 연산자 레이블이 **포함** 및 **포함하지 않음**이라도 매칭은 정확하고 대소문자를 구분합니다: `paid`는 `paid-extra`와 일치하지 않습니다. CLI에서 필터링하려면:

```bash
tuist bundle list --tags paid production
```

CLI, API(`?tags=paid,production`), 및 MCP `list_bundles` 도구(`tags: ["paid", "production"]`)는 지정된 **모든** 태그를 포함하는 번들을 반환합니다. API 업로드는 `bundle.custom_metadata.tags`를 허용하며; 목록 및 상세 응답은 `custom_metadata.tags`를 반환합니다. 태그가 없는 기존 번들은 이전과 동일하게 사용 가능합니다. 태그는 번들 목록을 필터링하지만, 크기 차트나 자동 비교 및 임계값 기준선은 변경하지 않습니다.

기존 클라이언트는 태그 없이 번들을 계속 업로드하고 읽을 수 있습니다. 업데이트된 클라이언트는 `custom_metadata`를 생략하는 이전 서버의 응답도 읽을 수 있습니다. 태그 저장 및 필터링에는 번들 태그를 지원하는 서버 버전이 필요합니다: 이전 서버는 업로드 메타데이터를 무시하고 태그 필터를 거부합니다. 업데이트된 클라이언트는 태그가 제공되지 않을 경우 업로드 메타데이터와 태그 쿼리 매개변수를 모두 생략합니다.

## 번들 크기 이해 {#understanding-sizes}

분석된 각 번들에 대해 Tuist는 두 가지 값을 보고합니다:

- **설치 크기**: 기기에 설치된 후 앱이 차지하는 공간입니다.
- **다운로드 크기**: 사용자가 다운로드하는 압축 크기입니다. Apple 번들의 경우 `.ipa`(아카이브 크기)에만 보고되며; `.xcarchive` 또는 `.app` 입력의 경우 사용할 수 없습니다.

크기는 바이트 단위로 저장되며 십진법 규약에 따라 표시됩니다. 여기서 1MB는 1,000,000바이트이고 1GB는 1,000,000,000바이트입니다 — 이는 Apple이 스토리지 및 앱 크기를 보고할 때 사용하는 것과 동일한 규약입니다([Apple 기기에서 스토리지 용량 측정 방법](https://support.apple.com/en-us/102119) 참조). 733,446,863바이트의 설치 크기는 733.4MB로 표시됩니다.

## 지속적 통합 {#continuous-integration}

시간에 따른 번들 크기를 추적하려면 CI에서 번들을 분석하세요. 먼저 CI가 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link>인지 확인하세요.

Tuist는 또한 번들을 보고할 프로젝트를 알아야 합니다. 아직 프로젝트를 연결하지 않았다면 `tuist init`를 실행하거나 핸들을 직접 선언하세요:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Gradle 프로젝트와 같이 Swift 매니페스트가 없는 프로젝트에는 <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link>를 사용하세요. 두 파일이 모두 존재할 경우 `Tuist.swift`가 우선합니다.

GitHub Actions 워크플로우 예시:

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

설정完成后, 시간에 따른 번들 크기 변화를 확인할 수 있습니다:

![번들 크기 그래프](/images/guides/features/bundle-size/bundle-size-graph.png)

## Pull/Merge 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 플랫폼과의 통합 필요**
>
> 자동 pull/merge 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">Tuist 프로젝트</.localized_link>를 <.localized_link href="/guides/server/authentication">Git 플랫폼</.localized_link>과 통합하세요.

Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결되면, `tuist inspect bundle`를 실행할 때마다 Tuist가 pull/merge 요청에 직접 댓글을 게시합니다:

![검사된 번들이 있는 GitHub 앱 댓글](/images/guides/features/bundle-size/github-app-with-bundles.png)

## 크기 임계값 {#size-thresholds}

> [!WARNING]
> **Git 포지와의 통합 필요**
>
> 크기 임계값을 사용하려면 [Tuist GitHub App](https://github.com/apps/tuist)을 프로젝트에 연결하세요. 프로젝트의 통합 페이지에서 이 작업을 수행할 수 있습니다.

크기 임계값을 사용하면 번들 크기가 기준 브랜치와 비교하여 구성된 백분율 또는 절대 크기를 초과할 때 pull 요청을 차단할 수 있습니다. 임계값이 위반되면 Tuist는 PR 커밋에 GitHub Check Run을 생성하여 크기 증가가 해결될 때까지 병합을 차단합니다:

![번들 크기 임계값 초과를 보여주는 PR 상태 확인](/images/guides/features/bundle-size/github-pr-check-status.png)

체크 런은 기준 크기, 현재 크기 및 구성된 단위의 변경 사항을 보여줍니다. 증가가 의도적인 경우 GitHub UI에서 **수락** 버튼을 클릭하여 직접 수락할 수 있습니다:

![임계값 위반을 보여주는 GitHub 체크 런](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 구성 {#size-thresholds-configuration}

임계값을 구성하려면 프로젝트의 **설정 > 번들** 탭으로 이동하세요:

![번들 크기 임계값 설정](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**설치 크기** 또는 **다운로드 크기**를 선택한 다음 **임계값 유형**을 선택하세요:

- **백분율(%)**: 기준 크기에 상대적인 성장을 제한합니다. `0.47`와 같은 소수점 백분율이 지원됩니다. 기존 백분율 임계값은 구성된 값과 동작을 유지합니다.
- **절대 크기(MB)**: 기준 크기와 무관하게 고정된 양만큼 성장을 제한합니다. 최대 1.5MB의 성장을 허용하려면 `1.5`를 입력하세요. MB는 십진 단위를 사용합니다: 1MB = 1,000,000바이트. 값은 양의 정수 바이트로 해석되어야 합니다.

![절대 번들 크기 성장 임계값 구성](/images/guides/features/bundle-size/absolute-size-threshold.png)

두 유형 모두 구성된 **기준 브랜치**에서 동일한 이름, 동일한 번들 유형(예: `.app` 또는 `.ipa`), 그리고 최소한 하나의 공통 플랫폼을 가진 최신 번들과 비교합니다. 따라서 시뮬레이터 `.app`는 시뮬레이터 `.app` 업로드와만 비교됩니다. 선택 사항인 **번들 이름**은 규칙을 해당 번들로 제한합니다. 성장이 한도를 **초과하는** 경우에만 검사가 실패합니다. 성장이 동일하거나 크기가 변경되지 않았거나 감소한 경우에는 통과합니다. 일치하는 기준이나 선택한 지표에 대한 기록된 크기가 없으면 규칙이 건너뜁니다. 절대 한도에는 크기가 0인 기준이 지원되지만, 백분율 성장이 정의되지 않으므로 백분율 한도는 이를 계속 건너뜁니다.

### 수락 가능한 사용자 제한 {#size-thresholds-approvals}

기본적으로 저장소에 쓰기 권한이 있는 모든 사용자는 크기 증가를 수락할 수 있습니다. GitHub가 해당 버튼 표시 대상이기 때문입니다. 범위를 좁히려면 **설정 > 번들** 아래에서 **수락 가능한 사용자**를 설정하세요:

- **모든 사용자**: 기본값입니다. 저장소에 쓰기 권한이 있는 모든 사용자.
- **선택한 GitHub 사용자**: 추가한 GitHub 사용자 이름만 해당됩니다.

목록에 없는 사용자는 설명과 함께 검사를 실패 상태로 유지하며, 버튼은 사용할 수 있는 사용자를 위해 그대로 표시됩니다.
