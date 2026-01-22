---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Google Workspace 조직을 보유하고 있으며 동일한 Google 호스팅 도메인으로 로그인하는 모든 개발자를 Tuist 조직에 추가하려면
다음을 설정하세요:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
설정 중인 조직의 도메인과 연결된 이메일로 Google에 인증되어야 합니다.
<!-- -->
:::

## Okta {#okta}

Okta와의 SSO는 기업 고객에게만 제공됩니다. 설정하시려면
[contact@tuist.dev](mailto:contact@tuist.dev)으로 문의해 주십시오.

이 과정에서 Okta SSO 설정을 지원해 드릴 담당자가 배정됩니다.

먼저, Okta 애플리케이션을 생성하고 Tuist와 연동되도록 설정해야 합니다:
1. Okta 관리자 대시보드로 이동하세요
2. 애플리케이션 > 애플리케이션 > 앱 통합 생성
3. "OIDC - OpenID Connect"와 "웹 애플리케이션"을 선택하십시오.
4. 애플리케이션의 표시 이름을 입력하세요. 예를 들어, "Tuist". [이
   URL](https://tuist.dev/images/tuist_dashboard.png)에 위치한 Tuist 로고를 업로드하세요.
5. 현재로서는 로그인 리다이렉트 URI는 그대로 두십시오
6. "할당" 항목에서 SSO 애플리케이션에 대한 원하는 접근 제어를 선택하고 저장하십시오.
7. After saving, the general settings for the application will be available.
   Copy the "Client ID" and "Client Secret". Also note your Okta organization
   URL (e.g., `https://your-company.okta.com`) – you will need to safely share
   all of these with your point of contact.
8. Once the Tuist team has configured the SSO, click on General Settings "Edit"
   button.
9. 다음 리다이렉트 URL을 붙여넣으세요: `https://tuist.dev/users/auth/okta/callback`
10. "Login initiated by"를 "Okta 또는 앱"으로 변경하십시오.
11. "사용자에게 애플리케이션 아이콘 표시" 선택
12. "로그인 시작 URL"을 `https://tuist.dev/users/auth/okta?organization_id=1` 로
    업데이트하십시오. `organization_id` 는 담당자가 제공할 것입니다.
13. "저장"을 클릭하세요.
14. Okta 대시보드에서 Tuist 로그인을 시작하십시오.

::: warning
<!-- -->
사용자는 Tuist가 현재 Okta 조직의 사용자 자동 프로비저닝 및 디프로비저닝을 지원하지 않으므로, 처음에 Okta 대시보드를 통해
로그인해야 합니다. Okta 대시보드를 통해 로그인하면 자동으로 귀하의 Tuist 조직에 추가됩니다.
<!-- -->
:::
