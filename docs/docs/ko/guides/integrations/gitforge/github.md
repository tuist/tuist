---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 통합 {#github}

Git 리포지토리는 대부분의 소프트웨어 프로젝트의 중심입니다. 당사는 GitHub와 통합하여 풀 리퀘스트에서 바로 Tuist 인사이트를 제공하고
기본 브랜치 동기화와 같은 일부 구성을 절약할 수 있습니다.

## 설정 {#설정}

Tuist GitHub 앱](https://github.com/marketplace/tuist)을 설치합니다. 설치가 완료되면 다음과 같은
리포지토리의 URL을 Tuist에 알려주어야 합니다:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
