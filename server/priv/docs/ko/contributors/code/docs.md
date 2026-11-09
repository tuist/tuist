---
{
  "title": "문서",
  "titleTemplate": ":title · 코드 · 기여자 · Tuist",
  "description": "Tuist 문서 사이트에 기여하세요."
}
---
# 문서 {#docs}

출처: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 용도 {#what-it-is-for}

문서 사이트는 Tuist의 제품 및 기여자 문서를 호스팅합니다. 이 사이트는 Tuist 서버의 일부로, Phoenix 애플리케이션이며 `server/priv/docs/en` 아래의 Markdown 페이지를 `/docs`에서 렌더링합니다.

## 기여 방법 {#how-to-contribute}

`server/priv/docs/en` 아래의 영어 페이지를 편집하세요. 번역은 별도로 관리되므로 다른 로케일 디렉터리는 편집하지 마세요. 사이드바는 `server/lib/tuist/docs_sidebar.ex`에 정의되어 있으며, 독자가 찾을 수 있도록 새 페이지를 여기에 추가하세요.

여러 페이지가 동일한 텍스트(예: 빌드 시스템 전반의 동일 섹션)를 공유하는 경우, 해당 페이지 옆에 이름이 `_`로 시작하는 파일에 내용을 넣고 `@snippet:` HTML 주석을 사용해 파일을 포함하세요. 불안정한 테스트 페이지에서 이와 같이 처리합니다. `_`로 시작하는 파일은 단독 페이지로 게시되지 않습니다.

### 로컬 설정 {#set-up-locally}

`server` 디렉터리에서 서버를 실행하며 [설정 지침](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)을 따르세요:

```bash
cd server
mise install
mise run dev
```

그런 다음 [http://localhost:8080/en/docs](http://localhost:8080/en/docs)을 엽니다.

### 생성된 콘텐츠 {#generated-content}

CLI 참조는 최신 CLI 릴리스의 명령어 사양에서 생성되므로 로컬에서 빌드할 필요가 없습니다.

ProjectDescription API 참조는 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)에서 DocC 사이트로 별도로 호스팅됩니다. 로컬에서 빌드하려면 저장소 루트에서 `mise run docs:project-description`를 실행하세요.
