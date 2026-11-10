---
{
  "title": "SCIM プロビジョニング",
  "titleTemplate": ":title | 認証 | 統合 | ガイド | Tuist",
  "description": "Okta または Microsoft Entra ID で SCIM プロビジョニングを設定する方法を学びます。"
}
---
# SCIM プロビジョニング {#scim-provisioning}

Tuist は SCIM 2.0 プロビジョニングをサポートしており、ID プロバイダーが組織メンバーの作成、更新、プロビジョニング解除を自動で行えます。

SCIM は、組織設定の **Authentication** タブから構成します。SCIM トークンは SCIM アクセスにスコープされた組織所有のアカウントトークンであり、生成時に一度だけ表示されます。

> [!NOTE]
> SCIM はメンバーシップとライフサイクルを管理します。<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> の代わりにはなりません。プロビジョニングされたユーザーが ID プロバイダー経由でサインインできるようにする場合は、SSO を別途構成してください。

プロビジョニングされたユーザーはすでに組織メンバーです。同じメールアドレスでサインインすると、そのメンバーシップによってプロバイダーの ID をリンクするための信頼関係が確立されます。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link> および <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">enrollment policy</.localized_link> は、まだプロビジョニングされていない、または組織に追加されていないユーザーを制御します。

## Okta {#okta}

Okta では Tuist 用に 2 つの別々のアプリケーションを使用します。

- Tuist へのサインイン用の **OIDC Web Application**
- Tuist へのユーザーおよびグループのプロビジョニング用の **SCIM 2.0 Test App (Header Auth)** アプリケーション

ユーザーが Okta でサインインできるようにする場合は、まず <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> を構成し、その後、以下の手順で SCIM プロビジョニングを構成してください。

### 手順 1: Tuist SCIM トークンを生成する {#okta-step-1}

1. Tuist で、組織の **Authentication** 設定タブに移動します。
2. **SCIM provisioning** セクションで、**SCIM endpoint URL** をコピーします。末尾は `/scim/v2` である必要があります。
3. **Generate token** をクリックします。
4. トークンに名前を付けます（例: `Okta`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度だけ表示されます。

### 手順 2: Okta SCIM アプリを追加する {#okta-step-2}

1. Okta 管理ダッシュボードで、**Applications > Applications > Browse App Catalog** に移動します。
2. **SCIM 2.0 Test App (Header Auth)** を検索して追加します。
3. 認識しやすい名前（例: `Tuist SCIM`）を付けます。
4. SCIM テストアプリのサインオン設定を完了します。Tuist はこのアプリをサインインには使用しません。サインインは SSO ガイドに記載されている OIDC アプリケーションによって処理されます。

### 手順 3: API 統合を構成する {#okta-step-3}

1. SCIM アプリの **Provisioning** タブを開きます。
2. **Settings > Integration** の下で、**Configure API Integration** または **Edit** をクリックします。
3. **Enable API integration** をチェックします。
4. Tuist の **SCIM endpoint URL** を Okta の **Base URL** フィールドに貼り付けます。
5. Tuist SCIM トークンを `Bearer ` プレフィックスを付けて **API Token** に貼り付けます。例: `Bearer tuist_scim_...`。Okta はこのフィールドを `Authorization` ヘッダーとして送信し、Tuist は bearer トークンを期待します。
6. Okta が Tuist の SCIM グループを読み取れるようにするには、**Import Groups** を有効にします。
7. **Test API Credentials** をクリックします。Okta から統合が正常に検証されたことが報告されるはずです。
8. **Save** をクリックします。

### 手順 4: プロビジョニングアクションを有効にする {#okta-step-4}

1. SCIM アプリの **Provisioning** タブで、**Settings > To App** を開きます。
2. **Edit** をクリックします。
3. 以下を有効にします。
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. **Save** をクリックします。

### 手順 5: ユーザーまたはグループを割り当てる {#okta-step-5}

1. SCIM アプリの **Assignments** タブを開きます。
2. Tuist にプロビジョニングするユーザーまたはグループを割り当てます。
3. SSO でサインインできるようにする場合、同じユーザーまたはグループを Okta OIDC アプリケーションにも割り当てます。
4. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

デプロビジョニングをテストするには、Okta でユーザーの割り当てを解除するか非アクティブ化し、Tuist 組織の **Members** タブからそのユーザーが消えていることを確認します。

### ロールの割り当て {#okta-assigning-roles}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> が 3 つあります。`admin`、`user`、`viewer` です。Tuist はロールごとに 1 つの SCIM グループを公開します。`Tuist Admins`、`Tuist Users`、`Tuist Viewers` です。Okta グループを **Group Push** でこれらにマップします。

1. 割り当てるロールごとに Okta グループを選択または作成し、SCIM アプリの **Assignments** タブでそれらのグループを割り当てます。
2. API 統合で **Import Groups** が有効になっていることを確認し、SCIM アプリの **Import** タブを開いて **Import Now** をクリックし、Okta が Tuist のグループを認識できるようにします。
3. SCIM アプリの **Push Groups** タブを開き、**Push Groups > Find groups by name** をクリックします。
4. Okta グループを選択し、プッシュアクションとして **Link Group** を選択して、対応する Tuist グループを選びます。Tuist は SCIM 経由でのグループ作成をサポートしていないため、新しいグループを作成するのではなく既存のグループにリンクしてください。
5. **Save** をクリックし、残りのロールについても繰り返します。

リンクされたグループにユーザーを追加すると、そのロールが付与されます。グループからユーザーを削除すると、組織がシングルサインオンメンバーを登録する際のデフォルトロールに戻ります。これは管理者が **Settings > Authentication** で変更しない限り `user` です。リンクされたグループに属さないユーザーもこのロールになります。グループからユーザーを削除しても組織からは削除されません。組織から削除するには、Okta で割り当てを解除するか非アクティブ化してください。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID は非ギャラリーのエンタープライズアプリケーションを通じて Tuist をプロビジョニングします。ユーザーが Entra ID でもサインインできるようにする場合、まず <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> を構成します。

シングルサインオン用に登録するアプリケーションとプロビジョニングに使用するエンタープライズアプリケーションは同じものにできます。プロビジョニングはエンタープライズアプリケーションのエントリで構成します。

### 手順 1: Tuist SCIM トークンを生成する {#entra-step-1}

1. Tuist で、組織の **Authentication** 設定タブに移動します。
2. **SCIM provisioning** セクションで、**SCIM endpoint URL** をコピーします。末尾は `/scim/v2` である必要があります。
3. **Generate token** をクリックします。
4. トークンに名前を付けます（例: `Entra ID`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度だけ表示されます。

### 手順 2: プロビジョニングを構成する {#entra-step-2}

1. Microsoft Entra 管理センターで、**Identity > Applications > Enterprise applications** に移動し、Tuist アプリケーションを開きます。
2. **Provisioning** を開き、**Provisioning Mode** を **Automatic** に設定します。
3. **Tenant URL** を Tuist SCIM エンドポイント URL に設定します。
4. **Secret Token** を Tuist SCIM トークンに設定します。トークンは単独で入力し、`Bearer ` プレフィックスは付けないでください。Entra ID がスキームを自動的に追加します。
5. **Test Connection** をクリックします。Entra ID から提供された認証情報が承認されたことが報告されるはずです。
6. 構成を保存します。

### 手順 3: 一致属性を設定する {#entra-step-3}

1. **Mappings** の下で、**Provision Microsoft Entra ID Users** を開きます。
2. `userPrincipalName` または `mail` が SCIM の `userName` 属性にマップされており、この属性が **Matching precedence 1** に使用されていることを確認します。
3. 存在する場合、一致属性から `externalId` を削除します。

Tuist は `userName` によってプロビジョニングされたユーザーを照合します。Entra ID が `externalId` として送信するディレクトリオブジェクト識別子は保存されないため、その属性でのフィルターは既存のメンバーを検出できず、プロビジョニングサイクルが予測不能な動作をする可能性があります。

### 手順 4: グループプロビジョニングを無効にする {#entra-step-4}

**Mappings** の下で、**Provision Microsoft Entra ID Groups** を無効に設定します。

Tuist の SCIM グループは作成可能なディレクトリグループではなく、組織ロールごとに固定されたグループであるため、ディレクトリグループのプロビジョニング試行は失敗します。代わりに以下のようにロールを割り当ててください。

### 手順 5: ユーザーを割り当ててプロビジョニングを開始する {#entra-step-5}

1. アプリケーションの **Users and groups** タブを開き、Tuist にプロビジョニングするユーザーまたはグループを割り当てます。
2. **Provisioning** に戻り、開始します。
3. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

Entra ID は独自のスケジュール（通常は 40 分ごと）でプロビジョニングを行うため、メンバーは即座には表示されません。単一のユーザーを直ちにテストするには、**Provision on demand** を使用します。

プロビジョニング解除をテストするには、Entra ID でユーザーの割り当てを解除または無効にし、Tuist 組織の **Members** タブからそのユーザーが消えていることを確認します。

後でプロビジョニングのスコープを変更した場合（例: **Sync all users and groups** から **Sync only assigned users and groups** へ）、その後で **Restart provisioning** をクリックしてください。Entra ID は再起動後にのみ、スコープ外になったユーザーのプロビジョニング解除を含めて新しいスコープを適用します。

### ロールの割り当て {#entra-assigning-administrators}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> が 3 つあります: `admin`、`user`、および `viewer`。Entra ID からこれらを設定するには:

1. **App registrations** で Tuist アプリケーションを開き、割り当てる Tuist ロールごとにアプリロールを追加します。**Allowed member types** を **Users/Groups** に設定し、**Value** を `admin`、`user`、または `viewer` に設定します。
2. エンタープライズアプリケーションの **Users and groups** タブで、各ユーザーまたはグループにそれらのアプリロールのいずれかを割り当てます。ユーザーは複数のアプリロールを持つことができます。Tuist は最も権限の高いロールを適用します。`admin` は `user` より優先され、`user` は `viewer` より優先されるため、異なるロールにマップされたグループに所属するユーザーには、それらのうち最も高いロールが付与されます。
3. **Provisioning > Mappings** の下で、**Advanced Options** ドロップダウンを開き、**Edit target User attributes** を選択します。**Type** を `String` に設定し、**Multi-Value** をチェックした状態で、`roles` という名前の属性を追加します。
4. **Provisioning > Mappings > Provision Microsoft Entra ID Users** の下で、**Add New Mapping** をクリックします。**Mapping type** を **Expression** に、**Expression** を `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` に、**Target attribute** を追加した `roles` 属性に設定します。
5. プロビジョニングのスコープを **Sync only assigned users and groups** に設定したままにしてください。`AssertiveAppRoleAssignmentsComplex` は **Sync all users and groups** と互換性がありません。

`AssertiveAppRoleAssignmentsComplex` はユーザーが持つすべてのアプリロールを送信し、削除も送信するため、Entra ID でロールを取り除くと、ユーザーは依然として保持している最も権限の高いロールにダウングレードされます。`roles[primary eq "True"].value` にマップされた `SingleAppRoleAssignment([appRoleAssignments])` も機能しますが、これは常に 1 つのロールのみを送信し、ユーザーが複数のロールを持っている場合に Entra ID がどれを選択するかは保証されません。

Entra ID でユーザーのアプリロールを変更すると、次のプロビジョニングサイクルで Tuist のロールが更新されます。アプリロールなしでプロビジョニングされたユーザー、または `admin`、`user`、`viewer` 以外の値を持つユーザーは、組織がシングルサインオンメンバーを登録する際のロール（管理者が **Settings > Authentication** で変更していない限り `user`）を得ます。

## ライフサイクルの動作 {#lifecycle-behavior}

ID プロバイダーがユーザーをプロビジョニングアプリケーションに割り当てると、Tuist はそのメールアドレスが Tuist に既知でない場合、ユーザーを作成して組織に追加します。メールアドレスが組織外の既存の Tuist ユーザーにすでに属している場合、Tuist はそのユーザーを追加し、その旨をメールで通知します。ただし、他の組織の SCIM 統合によってアカウントが作成された場合は例外です。その場合、Tuist はリクエストを `409` で拒否し、ID プロバイダーが他の組織が管理するアカウントを主張できないようにします。

ID プロバイダーは、組織がアカウントを独自に管理している間のみ、ユーザーのメールアドレス（`userName`）を変更できます。つまり、Tuist が SCIM 統合を通じてアカウントを作成し、その後ユーザーがパスワードを設定したり、組織のシングルサインオン以外のプロバイダーでサインインしたり、エージェント登録を要求したり、他の組織に参加したりしていない状態を指します。その他のユーザーの場合、Tuist は変更を `400` および `mutability` SCIM エラータイプで拒否します。同じリクエストで送信された非アクティブ化は引き続き適用されます。また、Tuist は、他の組織が検証したログインドメインや tuist.dev 上の Tuist 自身のドメインへのユーザー作成や、そのようなドメインへのユーザー名変更も拒否します。名前の変更により、ユーザーが以前のアドレスの制御権を証明した記録は消去されます。

ID プロバイダーがユーザーの割り当てを解除または非アクティブ化すると、Tuist はユーザーレコードと所有する作業を保持しながら、組織ロールを削除します。プロビジョニング解除はユーザーをグローバルに無効化するわけではありません。同じ Tuist ユーザーが他の組織に所属している可能性があるためです。

Tuist は 3 つの合成 SCIM グループを公開しています: `Tuist Admins`、`Tuist Users`、および `Tuist Viewers`。メンバーをグループに追加すると、その組織ロールが設定されます。現在のロールに一致するグループからメンバーを削除すると、登録ロールに戻り、メンバーシップ自体はユーザーの割り当て解除または非アクティブ化時にのみ終了します。ID プロバイダーは、SCIM の `roles` 属性を通じてユーザーのロールを設定することもでき、値は `admin`、`user`、または `viewer` です。複数の値を送信する ID プロバイダーの場合、最も権限の高い値が適用されます。`admin` は `user` より優先され、`user` は `viewer` より優先されます。

## サポートされている SCIM 機能 {#supported-scim-features}

Tuist は、ID プロバイダーがライフサイクル管理に必要な SCIM 2.0 エンドポイントをサポートしています:

- `/Users` 用の `POST`、`GET`、`PUT`、`PATCH`、および `DELETE`。
- `/Groups` 用の `GET` および `PATCH`。
- `/ServiceProviderConfig`、`/ResourceTypes`、および `/Schemas` の SCIM 検出エンドポイント。
