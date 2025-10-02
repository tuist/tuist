---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 인증 {#인증}

서버와 상호 작용하려면 CLI에서 [무기명
인증](https://swagger.io/docs/specification/authentication/bearer-authentication/)을
사용하여 요청을 인증해야 합니다. CLI는 사용자 또는 프로젝트로 인증을 지원합니다.

## 사용자 {#사용자}로서

컴퓨터에서 로컬로 CLI를 사용할 때는 사용자로 인증하는 것이 좋습니다. 사용자로 인증하려면 다음 명령을 실행해야 합니다:

```bash
tuist auth login
```

이 명령은 웹 기반 인증 절차를 안내합니다. 인증이 완료되면 CLI는 수명이 긴 새로 고침 토큰과 수명이 짧은 접근 토큰을
`~/.config/tuist/credentials` 에 저장합니다. 디렉터리의 각 파일은 인증한 도메인을 나타내며, 기본적으로
`tuist.dev.json` 입니다. 해당 디렉터리에 저장된 정보는 민감한 정보이므로 **안전하게 보관하십시오**.

CLI는 서버에 요청할 때 자동으로 자격 증명을 조회합니다. 액세스 토큰이 만료된 경우 CLI는 새로 고침 토큰을 사용하여 새 액세스 토큰을
얻습니다.

## 프로젝트로서 {#프로젝트로서}

지속적 통합과 같은 비대화형 환경에서는 대화형 플로우를 통해 인증할 수 없습니다. 이러한 환경에서는 프로젝트 범위 토큰을 사용하여 프로젝트로
인증하는 것이 좋습니다:

```bash
tuist project tokens create
```

CLI는 토큰이 환경 변수 `TUIST_CONFIG_TOKEN` 으로 정의되고 `CI=1` 환경 변수가 설정될 것으로 예상합니다. CLI는
토큰을 사용하여 요청을 인증합니다.

> [중요] 제한된 범위 프로젝트 범위 토큰의 권한은 CI 환경에서 프로젝트가 수행하기에 안전하다고 판단되는 작업으로 제한됩니다. 향후 토큰의
> 권한을 문서화할 계획입니다.
