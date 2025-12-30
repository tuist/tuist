---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## グーグル

Google Workspace組織を持っていて、同じGoogleホストドメインでサインインした開発者をTuist組織に追加したい場合は、次のように設定します：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: 警告
<!-- -->
設定するドメインの組織に関連付けられた電子メールを使用してGoogleで認証する必要があります。
<!-- -->
:::

## Okta {#okta}

Oktaを使用したSSOは、企業のお客様のみご利用いただけます。設定にご興味のある方は、[contact@tuist.dev](mailto:contact@tuist.dev)までご連絡ください。

プロセス中に、Okta SSOの設定をサポートする担当者が割り当てられます。

まず、Oktaアプリケーションを作成し、Tuistで動作するように設定する必要があります：
1. Oktaの管理ダッシュボードにアクセスする
2. アプリケーション > アプリケーション > アプリの統合を作成
3. OIDC - OpenID Connect "と "Webアプリケーション "を選択する。
4. アプリケーションの表示名、例えば "Tuist
   "を入力してください。このURL](https://tuist.dev/images/tuist_dashboard.png)にあるTuistのロゴをアップロードしてください。
5. サインインのリダイレクトURIは今のところそのままにしておく。
6. Assignments "でSSOアプリケーションへのアクセスコントロールを選択し、保存します。
7. 保存後、アプリケーションの一般設定が利用可能になります。クライアントID "と "クライアントシークレット "をコピーしてください。
8. Tuistチームは提供されたクライアントIDとシークレットでTuistサーバーを再デプロイする必要があります。これには最大1営業日かかります。
9. サーバーがデプロイされたら、General Settingsの "Edit "ボタンをクリックします。
10. 以下のリダイレクトURLを貼り付ける：`https://tuist.dev/users/auth/okta/callback`
13. Login initiated by」を「Either Okta or App」に変更します。
14. ユーザーにアプリケーションのアイコンを表示する」を選択する
15. Initiate login URL "を`https://tuist.dev/users/auth/okta?organization_id=1`
    で更新します。`organization_id` は、担当者から提供されます。
16. 保存」をクリックする。
17. OktaダッシュボードからTuistログインを開始する。
18. 以下のコマンドを実行して、Oktaドメインから署名したユーザーにTuist組織へのアクセスを自動的に与えます：
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: 警告
<!-- -->
Tuistは現在、Okta組織からのユーザーの自動プロビジョニングとデプロビジョニングをサポートしていないため、ユーザーは最初にOktaダッシュボードからサインインする必要があります。一度Oktaダッシュボードからサインインすると、自動的にTuist組織に追加されます。
<!-- -->
:::
