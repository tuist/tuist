---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

구글 워크스페이스 조직이 있고 동일한 구글 호스팅 도메인으로 로그인하는 모든 개발자를 튜이스트 조직에 추가하려는 경우, 다음과 같이 설정할 수
있습니다:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
도메인을 설정하려는 조직과 연결된 이메일을 사용하여 Google에 인증되어야 합니다.
<!-- -->
:::

## Okta {#okta}

Okta를 사용한 SSO는 기업 고객만 사용할 수 있습니다. 설정에 관심이 있는 경우
[contact@tuist.dev](mailto:contact@tuist.dev)로 문의하세요.

이 과정에서 Okta SSO를 설정하는 데 도움을 줄 담당자가 배정됩니다.

먼저, Okta 애플리케이션을 생성하고 Tuist와 함께 작동하도록 구성해야 합니다:
1. Okta 관리자 대시보드로 이동
2. 애플리케이션 > 애플리케이션 > 앱 통합 만들기
3. "OIDC - OpenID Connect" 및 "웹 애플리케이션"을 선택합니다.
4. 애플리케이션의 표시 이름(예: "Tuist")을 입력합니다. 이
   URL](https://tuist.dev/images/tuist_dashboard.png)에 있는 Tuist 로고를 업로드합니다.
5. 로그인 리디렉션 URI는 현재로서는 그대로 두세요.
6. '할당'에서 SSO 애플리케이션에 대한 원하는 액세스 제어를 선택하고 저장합니다.
7. 저장 후 애플리케이션의 일반 설정을 사용할 수 있습니다. "고객 ID"와 "고객 비밀"을 복사하여 담당자와 안전하게 공유해야 합니다.
8. 제공된 클라이언트 ID와 비밀번호로 Tuist 서버를 다시 배포해야 합니다. 이 작업에는 영업일 기준 최대 하루가 소요될 수 있습니다.
9. 서버가 배포되면 일반 설정 "편집" 버튼을 클릭합니다.
10. 다음 리디렉션 URL 붙여넣기: `https://tuist.dev/users/auth/okta/callback`
13. "로그인 시작 위치"를 "Okta 또는 앱"으로 변경합니다.
14. "사용자에게 애플리케이션 아이콘 표시"를 선택합니다.
15. `https://tuist.dev/users/auth/okta?organization_id=1` 으로 "로그인 URL 시작"을
    업데이트합니다. ` organization_id` 는 담당자가 제공합니다.
16. "저장"을 클릭합니다.
17. Okta 대시보드에서 Tuist 로그인을 시작합니다.
18. 다음 명령을 실행하여 Okta 도메인에서 로그인한 사용자에게 자동으로 Tuist 조직에 대한 액세스 권한을 부여하세요:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
현재 Tuist는 Okta 조직에서 사용자의 자동 프로비저닝 및 프로비저닝 해제를 지원하지 않으므로 사용자는 처음에 자신의 Okta 대시보드를
통해 로그인해야 합니다. 사용자가 Okta 대시보드를 통해 로그인하면 자동으로 Tuist 조직에 추가됩니다.
<!-- -->
:::
