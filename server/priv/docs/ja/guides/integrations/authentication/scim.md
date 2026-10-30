---
{
  "title": "SCIM プロビジョニング",
  "titleTemplate": ":title | Authentication | Integrations | Guides | Tuist",
  "description": "Okta または Microsoft Entra ID で SCIM プロビジョニングを設定する方法を学びます。"
}
---
# SCIM プロビジョニング {#scim-provisioning}

Tuist は SCIM 2.0 プロビジョニングに対応しており、ID プロバイダーが組織メンバーの作成、更新、プロビジョニング解除を自動的に行えます。

SCIM は、組織設定の **認証** タブから構成します。SCIM トークンは SCIM アクセスにスコープされた組織所有のアカウント トークンであり、生成時に一度だけ表示されます。

> [!NOTE]
> SCIM はメンバーシップとライフサイクルを管理します。<.localized_link href="/guides/integrations/authentication/sso">シングル サインオン</.localized_link> の代わりにはなりません。プロビジョニングされたユーザーが ID プロバイダー経由でもサインインできるようにする場合は、SSO を別途構成してください。

プロビジョニングされたユーザーはすでに組織のメンバーです。同じメールアドレスでサインインすると、そのメンバーシップによってプロバイダーの ID をリンクするための信頼関係が確立されます。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">検証済みログイン メール ドメイン</.localized_link> および <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">登録ポリシー</.localized_link> は、まだプロビジョニングされていない、または組織に追加されていないユーザーを制御します。

## Okta {#okta}

Okta では Tuist 用に 2 つの別々のアプリケーションを使用します。

- Tuist へのサインイン用の **OIDC Web アプリケーション**。
- Tuist へのユーザーとグループのプロビジョニング用の **SCIM 2.0 Test App (Header Auth)** アプリケーション。

ユーザーが Okta でサインインできるようにする場合は、まず <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> を構成し、その後、以下の手順で SCIM プロビジョニングを構成してください。

### 手順 1: Tuist SCIM トークンを生成する {#okta-step-1}

1. Tuist で、組織の **認証** 設定タブに移動します。
2. **SCIM プロビジョニング** セクションで、**SCIM エンドポイント URL** をコピーします。`/scim/v2` で終わっているはずです。
3. **トークンを生成** をクリックします。
4. トークンに名前を付けます（例: `Okta`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度だけ表示されます。

### 手順 2: Okta SCIM アプリを追加する {#okta-step-2}

1. Okta 管理ダッシュボードで、**Applications > Applications > Browse App Catalog** に移動します。
2. **SCIM 2.0 Test App (Header Auth)** を検索して追加します。
3. 認識しやすい名前（例: `Tuist SCIM`）を付けます。
4. SCIM テスト アプリのサインオン設定を完了します。Tuist はこのアプリをサインインには使用しません。サインインは SSO ガイドの OIDC アプリケーションによって処理されます。

### 手順 3: API 統合を構成する {#okta-step-3}

1. SCIM アプリの **Provisioning** タブを開きます。
2. **Settings > Integration** の下で、**Configure API Integration** または **Edit** をクリックします。
3. **Enable API integration** をチェックします。
4. Tuist の **SCIM エンドポイント URL** を Okta の **Base URL** フィールドに貼り付けます。
5. Tuist SCIM トークンを `Bearer ` プレフィックス付きで **API Token** に貼り付けます。例: `Bearer tuist_scim_...`。Okta はこのフィールドを `Authorization` ヘッダーとして送信し、Tuist は bearer トークンを期待します。
6. Okta が Tuist の SCIM グループを読み取れるようにする場合は、**Import Groups** を有効にします。
7. **Test API Credentials** をクリックします。Okta は統合が正常に検証されたことを報告するはずです。
8. **Save** をクリックします。

### 手順 4: プロビジョニング アクションを有効にする {#okta-step-4}

1. SCIM アプリの **Provisioning** タブで、**Settings > To App** を開きます。
2. **Edit** をクリックします。
3. 以下を有効にします。
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. **Save** をクリックします。

### 手順 5: ユーザーまたはグループを割り当てる {#okta-step-5}

1. SCIM アプリの **Assignments** タブを開きます。
2. Tuist にプロビジョニングされるユーザーまたはグループを割り当てます。
3. SSO でサインインできるようにする場合も、同じユーザーまたはグループを Okta OIDC アプリケーションに割り当てます。
4. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

プロビジョニング解除をテストするには、Okta でユーザーの割り当てを解除するか無効にし、Tuist 組織の **Members** タブからそのユーザーが消えていることを確認します。

### ロールの割り当て {#okta-assigning-roles}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">ロール</.localized_link> が 3 つあります: `admin`、`user`、および `viewer`。Tuist はロールごとに 1 つの SCIM グループを公開します: `Tuist Admins`、`Tuist Users`、および `Tuist Viewers`。**Group Push** を使用して Okta グループをこれらにマップします:

1. 割り当てる各ロールに対して Okta グループを選択または作成し、SCIM アプリの **Assignments** タブでそれらのグループを割り当てます。
2. API 統合で **Import Groups** が有効になっていることを確認し、SCIM アプリの **Import** タブを開いて **Import Now** をクリックし、Okta が Tuist のグループを認識できるようにします。
3. SCIM アプリの **Push Groups** タブを開き、**Push Groups > Find groups by name** をクリックします。
4. Okta グループを選択し、プッシュ アクションとして **Link Group** を選択して、一致する Tuist グループを選びます。Tuist は SCIM 経由でのグループ作成をサポートしていないため、新しいグループを作成するのではなく既存のグループにリンクします。
5. **Save** をクリックし、残りのロールについても繰り返します。

リンクされたグループにユーザーを追加すると、そのロールが付与されます。グループからユーザーを削除すると、組織がシングル サインオン メンバーを登録するロールに戻ります。これは、管理者が **Settings > Authentication** で変更しない限り `user` です。リンクされたグループに属していないユーザーもこのロールになります。グループからユーザーを削除しても組織からは削除されません。それを行うには、Okta で割り当てを解除するか無効にします。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID は非ギャラリーのエンタープライズ アプリケーションを通じて Tuist をプロビジョニングします。ユーザーが Entra ID でもサインインできるようにする場合は、まず <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> を構成します。

シングル サインオン用に登録するアプリケーションと、プロビジョニングに使用するエンタープライズ アプリケーションは同じものにできます。プロビジョニングはエンタープライズ アプリケーション エントリで構成されます。

### 手順 1: Tuist SCIM トークンを生成する {#entra-step-1}

1. Tuist で、組織の **Authentication** 設定タブに移動します。
2. **SCIM provisioning** セクションで、**SCIM エンドポイント URL** をコピーします。これは `/scim/v2` で終わるはずです。
3. **トークンを生成** をクリックします。
4. トークンに名前を付けます（例: `Entra ID`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度だけ表示されます。

### 手順 2: プロビジョニングを構成する {#entra-step-2}

1. Microsoft Entra 管理センターで、**Identity > Applications > Enterprise applications** に移動し、Tuist アプリケーションを開きます。
2. **Provisioning** を開き、**Provisioning Mode** を **Automatic** に設定します。
3. **Tenant URL** を Tuist SCIM エンドポイント URL に設定します。
4. **Secret Token** を Tuist SCIM トークンに設定します。`Bearer ` プレフィックスなしでトークン単独で入力してください。Entra ID がスキームを自動的に追加します。
5. **Test Connection** をクリックします。Entra ID は、提供された資格情報が承認されていることを報告するはずです。
6. 構成を保存します。

### 手順 3: 一致属性を設定する {#entra-step-3}

1. **Mappings** の下で、**Provision Microsoft Entra ID Users** を開きます。
2. `userPrincipalName` または `mail` が SCIM `userName` 属性にマップされており、この属性が **Matching precedence 1** に使用されていることを確認します。
3. 存在する場合は、一致属性から `externalId` を削除します。

Tuist は `userName` によってプロビジョニングされたユーザーを照合します。Entra ID が `externalId` として送信するディレクトリ オブジェクト識別子を保存しないため、その属性によるフィルターは既存のメンバーを見つけられず、プロビジョニング サイクルが予測不能な動作をする可能性があります。

### 手順 4: グループ プロビジョニングを無効にする {#entra-step-4}

**Mappings** の下で、**Provision Microsoft Entra ID Groups** を無効に設定します。

Tuist の SCIM グループは作成可能なディレクトリ グループではなく、組織ロールごとに固定されたグループであるため、ディレクトリ グループのプロビジョニングを試みると失敗します。代わりに、以下で説明するようにロールを割り当てます。

### 手順 5: ユーザーを割り当ててプロビジョニングを開始する {#entra-step-5}

1. アプリケーションの **Users and groups** タブを開き、Tuist にプロビジョニングされるユーザーまたはグループを割り当てます。
2. **Provisioning** に戻り、開始します。
3. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

Entra ID は独自のスケジュールでプロビジョニングを実行します。通常は 40 分ごとであるため、メンバーは即時には表示されません。単一のユーザーを直ちにテストするには、**Provision on demand** を使用してください。

プロビジョニング解除をテストするには、Entra ID でユーザーの割り当てを解除するか無効にし、Tuist 組織の **Members** タブからそのユーザーが消えていることを確認します。

後でプロビジョニングのスコープを変更した場合（例: **Sync all users and groups** から **Sync only assigned users and groups** へ）、その後で **Restart provisioning** をクリックしてください。Entra ID は再起動後にのみ、スコープ外になったユーザーのプロビジョニング解除を含めて新しいスコープを適用します。

### ロールの割り当て {#entra-assigning-administrators}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> が 3 つあります: `admin`、`user`、および `viewer`。Entra ID からこれらを設定するには:

1. **App registrations** で Tuist アプリケーションを開き、割り当てたい Tuist ロールごとにアプリ ロールを追加します。**Allowed member types** を **Users/Groups** に、**Value** を `admin`、`user`、または `viewer` に設定します。
2. エンタープライズ アプリケーションの **Users and groups** タブで、各ユーザーまたはグループにそれらのアプリ ロールのいずれかを割り当てます。ユーザーは複数のアプリ ロールを持つことができます。Tuist は最も特権の高いロールを適用します。`admin` は `user` より優先され、`user` は `viewer` より優先されるため、異なるロールにマップされたグループに所属するユーザーには、それらのうち最も高いロールが適用されます。
3. **Provisioning > Mappings** の下で、**Advanced Options** ドロップダウンを開き、**Edit target User attributes** を選択します。`roles` という名前の属性を追加し、**Type** を `String` に設定して、**Multi-Value** をチェックします。
4. **Provisioning > Mappings > Provision Microsoft Entra ID Users** の下で、**Add New Mapping** をクリックします。**Mapping type** を **Expression** に、**Expression** を `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` に、**Target attribute** を追加した `roles` 属性に設定します。
5. プロビジョニングのスコープを **Sync only assigned users and groups** に設定したままにしてください。`AssertiveAppRoleAssignmentsComplex` は **Sync all users and groups** と互換性がありません。

`AssertiveAppRoleAssignmentsComplex` はユーザーが持つすべてのアプリ ロールを送信し、削除も送信するため、Entra ID でロールを取り除くと、ユーザーは依然として保持している最も特権の高いロールにダウングレードされます。`SingleAppRoleAssignment([appRoleAssignments])` を `roles[primary eq "True"].value` にマップする方法も機能しますが、これは常に 1 つのロールのみを送信し、ユーザーが複数のロールを持っている場合に Entra ID がどれを選ぶかの保証はありません。

Entra ID でユーザーのアプリ ロールを変更すると、次のプロビジョニング サイクルで Tuist のロールが更新されます。アプリ ロールなしでプロビジョニングされたユーザー、または `admin`、`user`、`viewer` 以外の値を持つユーザーは、組織がシングル サインオン メンバーを登録する際のロールを取得します。管理者が **Settings > Authentication** で変更していない限り、これは `user` です。

## ライフサイクルの動作 {#lifecycle-behavior}

ID プロバイダーがユーザーをプロビジョニング アプリケーションに割り当てると、Tuist はそのメールアドレスが Tuist に既知でない場合にユーザーを作成し、組織に追加します。メールアドレスがすでに組織外の既存の Tuist ユーザーに属している場合、Tuist はリクエストを拒否し、IdP がその組織でまだ管理していないユーザーを claiming することを防ぎます。

ID プロバイダーがユーザーの割り当てを解除するか無効にすると、Tuist はユーザー レコードと所有する作業を保持しながら、組織ロールを削除します。同じ Tuist ユーザーが他の組織に所属できる可能性があるため、プロビジョニング解除によってユーザーがグローバルに無効になることはありません。

Tuist は 3 つの合成 SCIM グループを公開しています: `Tuist Admins`、`Tuist Users`、および `Tuist Viewers`。グループにメンバーを追加すると、その組織ロールが設定されます。現在のロールに一致するグループからメンバーを削除すると、登録時のロールに戻り、メンバーシップ自体はユーザーの割り当て解除または無効化時にのみ終了します。ID プロバイダーは、ユーザーの SCIM `roles` 属性を通じてロールを設定することもでき、値は `admin`、`user`、または `viewer` です。複数の値を送信する ID プロバイダーの場合、最も特権の高い値が適用されます。`admin` は `user` より優先され、`user` は `viewer` より優先されます。

## サポートされている SCIM 機能 {#supported-scim-features}

Tuist は、ID プロバイダーがライフサイクル管理に必要な SCIM 2.0 エンドポイントをサポートしています:

- `POST`、`GET`、`PUT`、`PATCH`、および `DELETE` （`/Users` 用）。
- `GET` および `PATCH` （`/Groups` 用）。
- `/ServiceProviderConfig`、`/ResourceTypes`、および `/Schemas` 用の SCIM ディスカバリー エンドポイント。
