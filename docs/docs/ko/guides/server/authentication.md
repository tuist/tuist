---
title: Authentication
titleTemplate: :title | Server | Guides | Tuist
description: CLI에서 Tuist 서버에 인증하는 방법을 배워봅니다.
---

# 인증 {#authentication}

서버와 상호 작용하기 위해 CLI는 [Bearer 인증](https://swagger.io/docs/specification/authentication/bearer-authentication/)을 사용하여 요청을 인증해야 합니다. CLI는 사용자 또는 프로젝트로 인증하는 것을 지원합니다.

## 사용자로 인증 {#as-a-user}

로컬에서 CLI를 사용할 때 사용자로 인증하는 것을 권장합니다. 사용자로 인증하기 위해 다음의 명령어를 수행해야 합니다:

```bash
tuist auth login
```

이 명령어는 웹 기반 인증 절차를 안내합니다. 인증을 완료하면, CLI는 `~/.config/tuist/credentials`에 오래 지속되는 리프레시 토큰과 일시적인 접근 토큰을 저장합니다. 디렉토리에 각 파일은 인증한 도메인을 나타내며 기본값은 `cloud.tuist.io.json` 이어야 합니다. 해당 디렉토리에 저장된 정보는 민감한 정보이므로 **안전하게 보관해야 합니다**.

CLI는 서버에 요청을 보낼 때 자동으로 자격 증명을 조회합니다. 접근 토근이 만료되면, CLI는 새로운 접근 토큰을 얻기 위해 리프레시 토큰을 사용합니다.

## 프로젝트로 인증 {#as-a-project}

CI와 같은 환경에서는 이런 상호 작용하며 인증할 수 없습니다. 이러한 환경에서는 프로젝트 범위의 토큰을 사용하여 프로젝트로 인증하는 것을 권장합니다:

```bash
tuist project tokens create
```

CLI는 토큰이 환경 변수 `TUIST_CONFIG_TOKEN`에 정의되어야 하고, `CI=1` 환경 변수도 설정되어야 합니다. CLI는 요청을 인증하기 위해 토큰을 사용합니다.

> [!IMPORTANT] 제한된 범위\
> 프로젝트 범위의 토큰 권한은 CI 환경에서 프로젝트가 수행할 수 있는 안전한 작업으로 제한됩니다. 우리는 향후 토큰이 가진 권한에 대한 문서를 제공할 예정입니다.
