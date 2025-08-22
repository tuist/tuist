---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Tuist를 다른 툴과 서비스에 연결하는 방법을 배워봅니다."
}
---
# Integrations {#integrations}

우리는 개발자들이 [GitHub](https://github.com)에서 Pull Request를 검토하거나 [Slack](https://slack.com)에서 팀과 소통하는 것과 같이 코딩 환경 밖에서도 시간을 보내기 때문에 개발자들이 있는 곳에서 그들을 만나야 한다고 생각합니다. 그래서 우리는 Tuist를 워크플로우에서 더 쉽게 사용할 수 있도록 인기있는 툴과 서비스와의 통합을 구축했습니다. 이 페이지에서는 현재 지원하고 있는 통합 목록을 나타냅니다.

## Git 플랫폼 {#git-platforms}

Git 리포지토리는 대부분의 소프트웨어 프로젝트에서 핵심적인 역할을 하고 있습니다. 우리는 Git 플랫폼과 통합하여 Pull Request에서 바로 Tuist와 관련된 유용한 정보를 제공하거나 기본 브랜치 동기화와 같은 설정을 자동으로 처리합니다.

### GitHub {#github}

[Tuist GitHub 앱](https://github.com/marketplace/tuist)을 설치합니다. 설치하면, Tuist에 리포지토리 URL을 알려줘야 합니다, 예를 들어:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
