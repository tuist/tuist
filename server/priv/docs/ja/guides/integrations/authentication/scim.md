---
{
  "title": "SCIM プロビジョニング",
  "titleTemplate": ":title | 認証 | インテグレーション | ガイド | Tuist",
  "description": "Okta または Microsoft Entra ID で SCIM プロビジョニングを設定する方法を学びます。"
}
---
# SCIM プロビジョニング {#scim-provisioning}

Tuist は SCIM 2.0 プロビジョニングをサポートしており、ID プロバイダーが組織メンバーの作成、更新、プロビジョニング解除を自動的に行えます。

SCIM は組織設定の **Authentication** タブから構成します。SCIM トークンは SCIM アクセスにスコープされた組織所有のアカウントトークンであり、生成時に一度だけ表示されます。

> [!NOTE]
> SCIM はメンバーシップとライフサイクルを管理します。<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> の代わりにはなりません。プロビジョニングされたユーザーが ID プロバイダー経由でサインインする必要がある場合は、SSO を別途構成してください。

プロビジョニングされたユーザーはすでに組織メンバーです。同じメールアドレスでサインインすると、そのメンバーシップによりプロバイダーの ID をリンクするための信頼関係が確立されます。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link> と <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">enrollment policy</.localized_link> は、まだプロビジョニングされていない、または組織に追加されていないユーザーを制御します。

## Okta {#okta}

Okta では Tuist 用に 2 つの別々のアプリケーションを使用します。

- Tuist へのサインイン用の **OIDC Web Application**
- Tuist へのユーザーとグループのプロビジョニング用の **SCIM 2.0 Test App (Header Auth)** アプリケーション

ユーザーが Okta でサインインする必要がある場合は、まず <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> を構成し、その後以下の手順で SCIM プロビジョニングを構成してください。

### ステップ 1: Tuist SCIM トークンを生成する {#okta-step-1}

1. Tuist で、組織の **Authentication** 設定タブに移動します。
2. **SCIM provisioning** セクションで、**SCIM endpoint URL** をコピーします。末尾は `/scim/v2` である必要があります。
3. **Generate token** をクリックします。
4. トークンに名前を付けます（例: `Okta`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度しか表示されません。

### ステップ 2: Okta SCIM アプリを追加する {#okta-step-2}

1. Okta 管理ダッシュボードで、**Applications > Applications > Browse App Catalog** に移動します。
2. **SCIM 2.0 Test App (Header Auth)** を検索して追加します。
3. 認識しやすい名前（例: `Tuist SCIM`）を付けます。
4. SCIM テストアプリのサインオン設定を完了します。Tuist はこのアプリをサインインには使用しません。サインインは SSO ガイドの OIDC アプリケーションによって処理されます。

### ステップ 3: API 統合を構成する {#okta-step-3}

1. SCIM アプリの **Provisioning** タブを開きます。
2. **Settings > Integration** の下で、**Configure API Integration** または **Edit** をクリックします。
3. **Enable API integration** をチェックします。
4. Tuist の **SCIM endpoint URL** を Okta の **Base URL** フィールドに貼り付けます。
5. Tuist SCIM トークンを `Bearer ` プレフィックス付きで **API Token** に貼り付けます。例: `Bearer tuist_scim_...`。Okta はこのフィールドを `Authorization` ヘッダーとして送信し、Tuist は bearer トークンを想定しています。
6. Okta が Tuist の SCIM グループを読み取れるようにする場合は、**Import Groups** を有効にします。
7. **Test API Credentials** をクリックします。Okta から統合が正常に検証されたことが報告されるはずです。
8. **Save** をクリックします。

### ステップ 4: プロビジョニングアクションを有効にする {#okta-step-4}

1. SCIM アプリの **Provisioning** タブで、**Settings > To App** を開きます。
2. **Edit** をクリックします。
3. 以下を有効にします。
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. **Save** をクリックします。

### ステップ 5: ユーザーまたはグループを割り当てる {#okta-step-5}

1. SCIM アプリの **Assignments** タブを開きます。
2. Tuist にプロビジョニングされるユーザーまたはグループを割り当てます。
3. SSO でサインインできるようにする場合も、同じユーザーまたはグループを Okta OIDC アプリケーションに割り当てます。
4. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

デプロビジョニングをテストするには、Okta でユーザーの割り当てを解除するか無効化し、そのユーザーが Tuist 組織の **Members** タブから消えていることを確認します。

### ロールの割り当て {#okta-assigning-roles}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> が 3 つあります。`admin`、`user`、`viewer` です。Tuist はロールごとに 1 つの SCIM グループを公開します。`Tuist Admins`、`Tuist Users`、`Tuist Viewers` です。Okta グループを **Group Push** でこれらにマッピングします。

1. 割り当てる各ロールに対して Okta グループを選択または作成し、SCIM アプリの **Assignments** タブでそれらのグループを割り当てます。
2. API 統合で **Import Groups** が有効になっていることを確認し、SCIM アプリの **Import** タブを開いて **Import Now** をクリックし、Okta が Tuist のグループを認識できるようにします。
3. SCIM アプリの **Push Groups** タブを開き、**Push Groups > Find groups by name** をクリックします。
4. Okta グループを選択し、プッシュアクションとして **Link Group** を選択して、一致する Tuist グループを選びます。Tuist は SCIM 経由でのグループ作成をサポートしていないため、新しいグループを作成するのではなく既存のグループにリンクします。
5. **Save** をクリックし、残りのロールについても繰り返します。

リンクされたグループにユーザーを追加すると、そのロールが付与されます。グループからユーザーを削除すると、組織がシングルサインオンメンバーに登録するロールに戻ります。管理者が **Settings > Authentication** で変更していない限り、これは `user` です。どのリンクされたグループにも属していないユーザーも、このロールになります。グループからユーザーを削除しても、組織から削除されるわけではありません。それを行うには、Okta で割り当てを解除するか無効化します。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID は非ギャラリーのエンタープライズアプリケーションを通じて Tuist をプロビジョニングします。ユーザーが Entra ID でもサインインできるようにする場合は、まず <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> を構成します。

シングルサインオン用に登録するアプリケーションと、プロビジョニングに使用するエンタープライズアプリケーションは同じものにできます。プロビジョニングはエンタープライズアプリケーションのエントリで構成します。

### ステップ 1: Tuist SCIM トークンを生成する {#entra-step-1}

1. Tuist で、組織の **Authentication** 設定タブに移動します。
2. **SCIM provisioning** セクションで、**SCIM endpoint URL** をコピーします。末尾は `/scim/v2` であるはずです。
3. **Generate token** をクリックします。
4. トークンに名前を付けます（例: `Entra ID`）。
5. 生成されたトークンをコピーします。Tuist ではトークンは一度しか表示されません。

### ステップ 2: プロビジョニングを構成する {#entra-step-2}

1. Microsoft Entra 管理センターで、**Identity > Applications > Enterprise applications** に移動し、Tuist アプリケーションを開きます。
2. **Provisioning** を開き、**Provisioning Mode** を **Automatic** に設定します。
3. **Tenant URL** を Tuist SCIM エンドポイント URL に設定します。
4. **Secret Token** を Tuist SCIM トークンに設定します。`Bearer ` プレフィックスなしでトークン単独で入力してください。Entra ID がスキームを自動的に追加します。
5. **Test Connection** をクリックします。Entra ID から、提供された認証情報が承認されていることが報告されるはずです。
6. 構成を保存します。

### ステップ 3: 一致属性を設定する {#entra-step-3}

1. **Mappings** の下で、**Provision Microsoft Entra ID Users** を開きます。
2. `userPrincipalName` または `mail` が SCIM の `userName` 属性にマッピングされており、この属性が **Matching precedence 1** に使用されていることを確認します。
3. 存在する場合は、一致属性から `externalId` を削除します。

Tuist は `userName` によってプロビジョニングされたユーザーを照合します。Entra ID が `externalId` として送信するディレクトリオブジェクト識別子は保存しないため、その属性でのフィルターは既存のメンバーを見つけられず、プロビジョニングサイクルが予測不能な動作をする可能性があります。

### ステップ 4: グループプロビジョニングを無効にする {#entra-step-4}

**Mappings** の下で、**Provision Microsoft Entra ID Groups** を無効に設定します。

Tuist の SCIM グループは、作成できるディレクトリグループではなく、組織ロールごとに固定されたグループです。そのため、ディレクトリグループのプロビジョニングを試みると失敗します。代わりに、以下のようにロールを割り当てます。

### ステップ 5: ユーザーを割り当ててプロビジョニングを開始する {#entra-step-5}

1. アプリケーションの **Users and groups** タブを開き、Tuist にプロビジョニングされるユーザーまたはグループを割り当てます。
2. **Provisioning** に戻り、開始します。
3. Tuist の **Members** タブを確認し、割り当てられたユーザーが組織に表示されていることを検証します。

Entra ID は独自のスケジュール（通常は 40 分ごと）でプロビジョニングを行うため、メンバーは即座には表示されません。単一のユーザーを直ちにテストするには、**Provision on demand** を使用します。

プロビジョニング解除をテストするには、Entra ID でユーザーの割り当てを解除するか無効にし、Tuist 組織の **Members** タブからそのユーザーが消えていることを確認します。

後でプロビジョニングのスコープを変更した場合（例：**Sync all users and groups** から **Sync only assigned users and groups** へ）、その後で **Restart provisioning** をクリックしてください。Entra ID は、再起動後にのみ、スコープ外になったユーザーのプロビジョニング解除を含む新しいスコープを適用します。

### ロールの割り当て {#entra-assigning-administrators}

Tuist には <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> が 3 つあります。`admin`、`user`、および `viewer` です。Entra ID からこれらを設定するには：

1. **App registrations** で Tuist アプリケーションを開き、割り当てたい Tuist ロールごとにアプリロールを追加します。**Allowed member types** を **Users/Groups** に、**Value** を `admin`、`user`、または `viewer` に設定します。
2. エンタープライズアプリケーションの **Users and groups** タブで、各ユーザーまたはグループにそれらのアプリロールのいずれかを割り当てます。ユーザーは複数のアプリロールを持つことができます。Tuist は最も権限の高いロールを適用します。`admin` は `user` より優先され、`user` は `viewer` より優先されるため、異なるロールにマッピングされたグループに所属するユーザーには、それらのうち最も高いロールが適用されます。
3. **Provisioning > Mappings** の下で、**Advanced Options** ドロップダウンを開き、**Edit target User attributes** を選択します。`roles` という名前の属性を追加し、**Type** を `String` に設定して、**Multi-Value** にチェックを入れます。
4. **Provisioning > Mappings > Provision Microsoft Entra ID Users** の下で、**Add New Mapping** をクリックします。**Mapping type** を **Expression** に、**Expression** を `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` に、**Target attribute** を追加した `roles` 属性に設定します。
5. プロビジョニングのスコープを **Sync only assigned users and groups** に設定したままにしてください。`AssertiveAppRoleAssignmentsComplex` は **Sync all users and groups** と互換性がありません。

`AssertiveAppRoleAssignmentsComplex` はユーザーが持つすべてのアプリロールを送信し、削除も送信するため、Entra ID でロールを取り除くと、ユーザーは保持している中で最も権限の高いロールにダウングレードされます。`roles[primary eq "True"].value` にマッピングされた `SingleAppRoleAssignment([appRoleAssignments])` も機能しますが、これは常に 1 つのロールのみを送信し、ユーザーが複数のロールを持っている場合に Entra ID がどれを選択するかは保証されません。

Entra ID でユーザーのアプリロールを変更すると、次のプロビジョニングサイクルで Tuist のロールが更新されます。アプリロールなしでプロビジョニングされたユーザー、または `admin`、`user`、`viewer` 以外の値を持つユーザーは、組織がシングルサインオンメンバーを登録する際のロール（管理者が **Settings > Authentication** で変更していない限り `user`）になります。

## ライフサイクルの動作 {#lifecycle-behavior}

アイデンティティプロバイダーがユーザーをプロビジョニングアプリケーションに割り当てると、Tuist はそのメールアドレスが Tuist にまだ認識されていない場合にユーザーを作成し、組織に追加します。メールアドレスが組織外の既存の Tuist ユーザーにすでに属している場合、Tuist はそのユーザーを追加し、その旨をメールで通知します。ただし、他の組織の SCIM 統合によってアカウントが作成された場合は例外です。その場合、Tuist は `409` でリクエストを拒否し、アイデンティティプロバイダーが他の組織が管理するアカウントを主張できないようにします。

アイデンティティプロバイダーは、組織がアカウントを独自に管理している間のみ、ユーザーのメールアドレス（`userName`）を変更できます。これは、Tuist が SCIM 統合を通じてアカウントを作成し、その後ユーザーがパスワードを設定したり、組織のシングルサインオン以外のプロバイダーでサインインしたり、エージェント登録を主張したり、他の組織に参加したりしていないことを意味します。その他のユーザーの場合、Tuist は `400` および `mutability` SCIM エラータイプで変更を拒否します。同じリクエストで送信された無効化は依然として適用されます。Tuist は、他の組織が検証したログインドメインや、tuist.dev では Tuist 自身のドメインへのユーザーの作成や、ユーザーの名前変更も拒否します。名前変更を行うと、ユーザーが古いアドレスの制御権を証明したという記録は消去されます。

アイデンティティプロバイダーがユーザーの割り当てを解除するか無効にすると、Tuist はユーザーレコードと所有する作業を保持しながら、組織ロールを削除します。プロビジョニング解除はユーザーをグローバルに無効にするわけではありません。同じ Tuist ユーザーが他の組織に所属できるためです。

Tuist は 3 つの合成 SCIM グループを公開しています。`Tuist Admins`、`Tuist Users`、および `Tuist Viewers` です。グループにメンバーを追加すると、その組織ロールが設定されます。現在のロールに一致するグループからメンバーを削除すると、登録ロールに戻ります。メンバーシップ自体は、ユーザーの割り当てが解除されるか無効化されたときにのみ終了します。アイデンティティプロバイダーは、ユーザーの SCIM `roles` 属性を通じて、`admin`、`user`、または `viewer` の値でロールを設定することもできます。複数の値を送信するアイデンティティプロバイダーの場合、最も権限の高い値が適用されます。`admin` は `user` より優先され、`user` は `viewer` より優先されます。

## サポートされている SCIM 機能 {#supported-scim-features}

Tuist は、ライフサイクル管理に必要なアイデンティティプロバイダー向けの SCIM 2.0 エンドポイントをサポートしています：

- `/Users` 用の `POST`、`GET`、`PUT`、`PATCH`、および `DELETE`。
- `/Groups` 用の `GET` および `PATCH`。
- `/ServiceProviderConfig`、`/ResourceTypes`、および `/Schemas` の SCIM 検出エンドポイント。
