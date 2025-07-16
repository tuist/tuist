---
title: GitHub
titleTemplate: :title | Git forges | Integrations | Guides | Tuist
description: Learn how to integrate Tuist with GitHub for enhanced workflows.
---

# GitHub {#github}

Git 리포지토리는 대부분의 소프트웨어 프로젝트에서 핵심적인 역할을 하고 있습니다. 우리는 Git 플랫폼과 통합하여 Pull Request에서 바로 Tuist와 관련된 유용한 정보를 제공하거나 기본 브랜치 동기화와 같은 설정을 자동으로 처리합니다.

## Setup {#setup}

[Tuist GitHub 앱](https://github.com/marketplace/tuist)을 설치합니다. 설치하면, Tuist에 리포지토리 URL을 알려줘야 합니다, 예를 들어:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
