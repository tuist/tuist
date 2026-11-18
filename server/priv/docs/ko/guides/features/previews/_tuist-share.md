## tuist share로 트랙 관리하기 {#share-tracks}

`tuist share`로 배포하는 워크플로에서는 `--track`를 사용해 트랙을 선택하세요:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 릴리스 노트 {#release-notes}

환경 그룹에는 트랙을, 개별 빌드의 목적 설명에는 릴리스 노트를 사용하세요:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

`App`을 앱 이름, 애플리케이션 파일 경로 또는 실행 파일 배포 항목으로 바꾸고 `--executable` 옵션을 함께 사용하세요. 릴리스 노트는 선택 사항인 일반 텍스트로, 최대 10,000자까지 입력할 수 있습니다. 첫 번째 비어 있지 않은 줄이 미리보기 목록에서 한 줄 스니펫으로 표시되므로, 빌드 번호와 기타 식별 정보를 한눈에 확인할 수 있습니다. 긴 줄은 잘리며, 전체 노트는 상세 페이지에 표시됩니다. 검색 결과는 스니펫에 표시되지 않은 줄을 포함해 표시 이름과 전체 릴리스 노트를 대상으로 일치합니다. 여러 줄 노트도 지원되며, 예를 들어 `--release-notes "$(< release-notes.txt)"`와 같이 사용할 수 있습니다. 이는 앱의 표시 이름이나 트랙을 변경하지 않습니다.

### 호환성 {#preview-metadata-compatibility}

릴리스 노트는 빌드가 속한 미리보기를 변경하지 않습니다. 미리보기가 처음 받은 노트가 유지됩니다. 이후 업로드에서는 노트가 없는 미리보기에 노트를 추가할 수 있지만, 기존 노트를 덮어쓰거나 지울 수는 없습니다. 릴리스 노트 기능이 도입되기 전에 업로드된 미리보기는 노트 없이도 유효하게 유지됩니다.

셀프 호스팅 배포에서는 릴리스 노트와 트랙 필터링을 지원하는 서버 버전과 업데이트된 클라이언트가 필요합니다. 이전 서버는 노트를 무시합니다. 목록 엔드포인트의 트랙 및 검색 필터에 대해서는 [API 참조](https://tuist.dev/api/docs)를 확인하세요.

## 풀/머지 요청 댓글 {#pullmerge-request-comments}

> [!WARNING]
> **Git 포지 연동 필요**
>
> 풀/머지 요청에 자동으로 댓글을 추가하려면 <.localized_link href="/guides/server/accounts-and-projects">원격 프로젝트</.localized_link>를 Git 포지와 연동하세요: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>, 또는 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

Tuist 프로젝트가 Git 플랫폼과 연결되면, CI에서 애플리케이션 빌드가 성공한 후 <.localized_link href="/cli/share">`tuist share`</.localized_link>를 추가하세요. Tuist는 풀/머지 요청에 미리보기 링크를 직접 게시하므로, 리뷰어가 로컬 빌드 없이 테스트할 수 있습니다:

![Tuist Preview 링크가 포함된 GitHub 앱 댓글](/images/guides/features/github-app-with-preview.png)

## 자동화 {#automations}

`tuist share`에서 JSON 출력을 얻으려면 `--json`를 사용하세요:

```bash
tuist share --json
```

결과를 활용해 CI에서 Slack 메시지를 보내는 등 사용자 정의 자동화를 구성할 수 있습니다. `url` 키에는 전체 미리보기 링크가 포함되며, `qrCodeURL`는 기기에서 미리보기를 열기 위한 QR 코드 이미지를 가리킵니다:

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
