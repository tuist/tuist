---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# 문서 {#docs}

Source:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 용도 {#what-it-is-for}

문서 사이트는 Tuist의 제품 및 기여자 문서를 호스팅합니다. VitePress로 구축되었습니다.

## 기여 방법 {#how-to-contribute}

### 로컬 환경 설정 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 선택적 생성 데이터 {#optional-generated-data}

문서에 생성된 데이터를 일부 포함합니다:

- CLI 참조 데이터: `mise run generate-cli-docs`
- 프로젝트 매니페스트 참조 데이터: `mise run generate-manifests-docs`

이들은 선택 사항입니다. 문서가 이 요소들 없이도 렌더링되므로, 생성된 콘텐츠를 새로 고칠 필요가 있을 때만 실행하세요.
