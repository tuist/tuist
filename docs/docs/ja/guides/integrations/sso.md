---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## グーグル

Google Workspace 組織をお持ちで、同じ Google ホストドメインでサインインする開発者をすべて Tuist
組織に追加したい場合は、以下で設定できます：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: 警告
<!-- -->
設定するドメインの組織に関連付けられたメールアドレスでGoogleに認証されている必要があります。
<!-- -->
:::

## Okta {#okta}

OktaとのSSOはエンタープライズ顧客のみが利用可能です。設定をご希望の場合は、[contact@tuist.dev](mailto:contact@tuist.dev)までお問い合わせください。

プロセス中に、Okta SSOの設定を支援する担当者が割り当てられます。

まず、Oktaアプリケーションを作成し、Tuistと連携するように設定する必要があります：
1. Okta管理ダッシュボードに移動する
2. アプリケーション > アプリケーション > アプリ統合の作成
3. 「OIDC - OpenID Connect」と「Web Application」を選択してください
4. アプリケーションの表示名を入力してください。例：「Tuist」。Tuistのロゴを[このURL](https://tuist.dev/images/tuist_dashboard.png)からアップロードしてください。
5. サインインリダイレクトURIは現時点ではそのままにしておく
6. 「割り当て」でSSOアプリケーションへのアクセス制御を選択し、保存してください。
7. After saving, the general settings for the application will be available.
   Copy the "Client ID" and "Client Secret". Also note your Okta organization
   URL (e.g., `https://your-company.okta.com`) – you will need to safely share
   all of these with your point of contact.
8. Once the Tuist team has configured the SSO, click on General Settings "Edit"
   button.
9. 以下のリダイレクトURLを貼り付けてください：`https://tuist.dev/users/auth/okta/callback`
10. 「Login initiated by」を「Okta またはアプリ」に変更してください。
11. 「ユーザーにアプリケーションアイコンを表示する」を選択
12. Initiate login URL "を`https://tuist.dev/users/auth/okta?organization_id=1`
    で更新してください。`organization_id` は、担当者から提供されます。
13. 「保存」をクリックしてください。
14. OktaダッシュボードからTuistのログインを開始してください。

::: 警告
<!-- -->
ユーザーは最初にOktaダッシュボードからサインインする必要があります。Tuistは現在、Okta組織からのユーザーの自動プロビジョニングおよびデプロビジョニングをサポートしていないためです。Oktaダッシュボードからサインインすると、自動的にTuist組織に追加されます。
<!-- -->
:::
