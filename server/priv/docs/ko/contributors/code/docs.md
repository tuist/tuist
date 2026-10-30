---
{
  "title": "문서",
  "titleTemplate": ":title · 코드 · 기여자 · Tuist",
  "description": "Tuist 문서 사이트에 기여하세요."
}
---
# 문서 {#docs}

소스: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 용도 {#what-it-is-for}

문서 사이트는 Tuist의 제품 및 기여자 문서를 호스팅합니다. VitePress로 구축되었습니다.

## 기여 방법 {#how-to-contribute}

### 로컬 설정 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 선택적 생성 데이터 {#optional-generated-data}

문서에 일부 생성된 데이터를 포함합니다:

- CLI 참조 데이터: `mise run generate-cli-docs`

이들은 선택 사항입니다. 문서가 없어도 렌더링되므로, 생성된 콘텐츠를 새로 고쳐야 할 때만 실행하세요.

ProjectDescription API 참조는 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)에서 DocC 사이트로 별도로 호스팅됩니다. 로컬에서 빌드하려면 저장소 루트에서 `mise run docs:project-description`를 실행하세요.
