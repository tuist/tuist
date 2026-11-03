## tuist share로 트랙 관리 {#share-tracks}

`tuist share`로 배포하는 워크플로에서는 `--track`를 사용해 트랙을 선택하세요:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 릴리스 노트 {#release-notes}

환경 그룹에는 트랙을, 개별 빌드 목적에는 릴리스 노트를 사용하세요:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

`App`을 앱 이름, 애플리케이션 파일 경로 또는 실행 파일 배포와 해당 `--executable` 옵션으로 대체하세요. 릴리스 노트는 선택 사항인 일반 텍스트이며 최대 10,000자까지 입력할 수 있습니다. 첫 번째 비어 있지 않은 줄이 미리보기 목록에서 한 줄 스니펫으로 표시되므로 빌드 번호와 기타 식별 정보를 한눈에 확인할 수 있습니다. 긴 줄은 잘리며 전체 노트는 상세 페이지에 표시됩니다. 검색은 스니펫에 표시되지 않은 줄을 포함해 표시 이름과 전체 릴리스 노트를 일치시킵니다. 여러 줄 노트도 지원되며, 예를 들어 `--release-notes "$(< release-notes.txt)"`와 같이 사용할 수 있습니다. 이는 앱의 표시 이름이나 트랙을 변경하지 않습니다.

### 호환성 {#preview-metadata-compatibility}

릴리스 노트는 추가 메타데이터이며 미리보기 식별자의 일부가 아닙니다. 이전 및 최신 클라이언트의 업로드도 플랫폼 간에 동일한 미리보기로 그룹화됩니다. 첫 번째 비어 있지 않은 노트는 유지됩니다: 이후 업로드는 이전에 없던 노트를 채울 수 있지만 기존 노트를 덮어쓸 수는 없습니다. `release_notes`를 생략하거나 `null`를 보내거나 빈 문자열 또는 공백만 있는 문자열을 보내면 노트가 지워지지 않습니다. 기존 미리보기는 백필되지 않으며 노트 없이도 유효하게 유지됩니다.

목록 API의 선택적 `track` 쿼리 매개변수는 기존 트랙 저장 방식과 일관되게 대소문자를 구분하지 않고 전체 트랙 이름을 일치시킵니다. 모든 트랙을 나열하려면 이를 생략하거나 빈 값(`?track=`)을 보내세요. 트랙 이름은 고정된 값 목록이 아닌 개방형 문자열로 유지됩니다. `GET /api/projects/:account_handle/:project_handle/previews/tracks`는 정렬되고 대소문자를 구분하지 않고 그룹화된 이름별 트랙을 포함한 `{total_count, tracks: [{name, count}]}`를 반환하며, 빌드 목록과 동일한 미리보기 읽기 권한 하에 동작합니다. 카운트는 페이지네이션, 검색 및 선택된 트랙과 무관하게 전체 프로젝트를 대상으로 하며 총계에는 추적되지 않는 미리보기가 포함됩니다. 번들 식별자가 있는 목록 가능한 미리보기만 카운트에 포함됩니다. 목록 API는 또한 표시 이름이나 전체 릴리스 노트의 리터럴 대소문자 구분 없는 부분 문자열을 위한 선택적 `search`를 허용하며, 페이지네이션 전에 트랙과 결합됩니다. 기존 `display_name` 필터링은 정확히 일치합니다.

이전 클라이언트는 두 필드 중 어느 것도 보내지 않고 계속 미리보기를 업로드하고 나열할 수 있습니다. 새 클라이언트는 트랙이나 노트가 누락된 이전 응답을 수용하며 향후 서버에서 추가된 알 수 없는 응답 속성을 무시합니다. API 통합 역시 알 수 없는 응답 속성을 무시해야 추가 메타데이터의 호환성이 유지됩니다.

셀프 호스팅 배포는 이러한 기능을 사용하려면 릴리스 노트와 트랙 필터링을 지원하는 서버 버전과 업데이트된 클라이언트가 필요합니다. 이전 서버는 노트나 알 수 없는 쿼리 매개변수를 무시할 수 있습니다.

## 풀/머지 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 플랫폼과의 통합 필요**
>
> 자동 풀/머지 요청 댓글을 받으려면 <.localized_link href="/guides/server/accounts-and-projects">원격 프로젝트</.localized_link>를 <.localized_link href="/guides/server/authentication">Git 플랫폼</.localized_link>과 통합하세요.

Tuist 프로젝트가 Git 플랫폼과 연결되면 CI에서 애플리케이션 빌드가 성공한 후 <.localized_link href="/cli/share">`tuist share`</.localized_link>를 추가하세요. Tuist는 풀/머지 요청에 미리보기 링크를 직접 게시하므로 리뷰어가 로컬 빌드 없이 테스트할 수 있습니다:

![Tuist Preview 링크가 포함된 GitHub 앱 댓글](/images/guides/features/github-app-with-preview.png)

## 자동화 {#automations}

`tuist share`에서 JSON 출력을 얻으려면 `--json`를 사용하세요:

```bash
tuist share --json
```

결과를 CI에서 Slack 메시지를 게시하는 등 맞춤형 자동화에 활용하세요. `url` 키에는 전체 미리보기 링크가 포함되며 `qrCodeURL`는 기기에서 미리보기를 열기 위한 QR 코드 이미지를 가리킵니다:

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
