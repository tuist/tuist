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
7. 保存後、アプリケーションの一般設定が利用可能になります。「クライアントID」と「クライアントシークレット」をコピーしてください。担当者と安全に共有する必要があります。
8. Tuistチームは、提供されたクライアントIDとシークレットを使用してTuistサーバーを再デプロイする必要があります。これには最大1営業日を要する場合があります。
9. サーバーがデプロイされたら、一般設定の「編集」ボタンをクリックしてください。
10. 以下のリダイレクトURLを貼り付けてください：`https://tuist.dev/users/auth/okta/callback`
13. 「Login initiated by」を「Okta またはアプリ」に変更してください。
14. 「ユーザーにアプリケーションアイコンを表示する」を選択
15. Initiate login URL "を`https://tuist.dev/users/auth/okta?organization_id=1`
    で更新してください。`organization_id` は、担当者から提供されます。
16. 「保存」をクリックしてください。
17. OktaダッシュボードからTuistのログインを開始してください。
18. 以下のコマンドを実行することで、OktaドメインからサインアップしたユーザーにTuist組織への自動アクセス権を付与します：
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: 警告
<!-- -->
ユーザーは最初にOktaダッシュボードからサインインする必要があります。Tuistは現在、Okta組織からのユーザーの自動プロビジョニングおよびデプロビジョニングをサポートしていないためです。Oktaダッシュボードからサインインすると、自動的にTuist組織に追加されます。
<!-- -->
:::
