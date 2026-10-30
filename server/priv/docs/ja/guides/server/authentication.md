---
{
  "title": "認証",
  "titleTemplate": ":title | Server | ガイド | Tuist",
  "description": "CLI から Tuist サーバーへの認証方法を学びます。"
}
---
# 認証 {#authentication}

サーバーとやり取りするには、CLI は [ベアラ認証](https://swagger.io/docs/specification/authentication/bearer-authentication/) を使用してリクエストを認証する必要があります。CLI は、ユーザーとして、アカウントとして、または OIDC トークンを使用して認証することをサポートしています。

## ユーザーとして {#as-a-user}

マシン上でローカルに CLI を使用する場合は、ユーザーとして認証することをお勧めします。ユーザーとして認証するには、次のコマンドを実行してください:

```bash
tuist auth login
```

このコマンドを実行すると、Web ベースの認証フローが始まります。認証が完了すると、CLI は長寿命のリフレッシュトークンと短寿命のアクセストークンを `~/.config/tuist/credentials` に保存します。ディレクトリ内の各ファイルは、認証先のドメインを表しており、デフォルトでは `tuist.dev.json` になります。このディレクトリに保存される情報は機密性が高いので、**安全に保管してください**。

CLI はサーバーへのリクエスト時に自動的に資格情報を参照します。アクセストークンの有効期限が切れている場合、CLI はリフレッシュトークンを使用して新しいアクセストークンを取得します。

> [!NOTE]
> 組織でシングルサインオンを使用している場合は、ブラウザでエンタープライズログインオプションを選択し、勤務先のメールアドレスを入力してください。Tuist は、既存の組織メンバーシップまたは <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">検証済みのログイン用メールドメイン</.localized_link> からプロバイダーを検出できます。

## OIDC トークン {#oidc-tokens}

OpenID Connect (OIDC) をサポートする CI 環境では、長寿命のシークレットを管理する必要なく、Tuist が自動的に認証を行います。サポートされている CI 環境で実行すると、CLI は OIDC トークンプロバイダーを自動的に検出し、CI から提供されたトークンを Tuist のアクセストークンと交換します。

### サポートされているプロバイダー {#supported-ci-providers}

Tuist は以下の CI プロバイダーを認識し、リポジトリ接続を通じてそれらのトークンをプロジェクトにマッピングします:

- GitHub Actions
- CircleCI
- Bitrise

OpenID Connect トークンを発行する他のあらゆる ID プロバイダーは、アカウント内の現在および将来のすべてのプロジェクトに対して一度設定する [ワークロード ID 信頼ポリシー](#workload-identity-trust-policies) を介して認証できます。例: [Fly.io Machines](#flyio-machines)。

### OIDC 認証の設定 {#setting-up-oidc-authentication}

GitHub Actions、CircleCI、Bitrise の場合:

1. **リポジトリを Tuist に接続**: <.localized_link href="/guides/integrations/gitforge/github">GitHub 統合ガイド</.localized_link> に従って、GitHub リポジトリを Tuist プロジェクトに接続します。

2. **`tuist auth login` を実行**: CI ワークフローで、認証を必要とするコマンドの前に `tuist auth login` を実行します。CLI は CI 環境を自動的に検出し、OIDC を使用して認証を行います。

プロバイダー固有の設定例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

### ワークロード ID 信頼ポリシー {#workload-identity-trust-policies}

信頼ポリシーにより、デプロイメントプラットフォーム、Kubernetes クラスター、またはセルフマネージド CI システムなど、別の ID プロバイダーからのワークロードが、長寿命の Tuist シークレットなしでプロジェクトにアクセスできるようになります。プロバイダーは以下の条件を満たす必要があります:

- パブリックアドレスで HTTPS 経由で到達可能であること。Tuist はリダイレクトに従わず、セルフホスト型の Tuist サーバーからのものであっても、プライベートまたは内部ネットワークアドレスには接続しません。
- 非対称鍵で署名された JWT を発行すること。例: `RS256` または `ES256`。署名されていないトークンや共有シークレットで署名されたトークン (`HS256` など) は拒否されます。
- 署名鍵を JSON Web Key Set (JWKS) として固定の HTTPS URL で公開すること。レスポンスは最大 64 KiB で、鍵は最大 20 個まで含まれている必要があります。
- すべてのトークンに有効期限 (`exp`) を含めること。

GitHub Actions、CircleCI、Bitrise の発行者は、上記のリポジトリベースのフロー用に予約されており、信頼ポリシーでは使用できません。

> [!NOTE]
> セルフホスト型のロールアウトの場合、ワークロード ID を構成したりジョブを移行したりする前に、データベースマイグレーションを適用し、稼働中のすべての Tuist サーバーレプリカをアップグレードしてください。その後、CLI または Elixir 統合を `TUIST_OIDC_TOKEN` および `TUIST_OIDC_ACCOUNT` をサポートするバージョンにアップグレードします。既存の GitHub Actions、CircleCI、Bitrise ジョブはリポジトリベースの認証を引き続き使用するため、アカウントハンドルは不要です。本番ジョブを切り替える前に、意図したワークロードで短寿命トークンの交換とキャッシュ操作を検証してください。新しい交換を停止するには、ポリシーを削除します。すでに発行された Tuist アクセストークンの有効期限が切れるまで、最大 1 時間かかります。ポリシーを削除しても、これらのトークンは直ちに取り消されません。

#### ポリシーの作成 {#create-a-trust-policy}

Tuist ダッシュボードで、アカウントの **設定** > **認証** を開き、**ワークロード ID** セクションを見つけます。アカウント管理者 (または個人アカウントの所有者) である必要があります。各アカウントには最大 20 件のポリシーを設定できます。アカウント全体の CI アクセスのために ID を一度設定します。プロジェクトの選択は不要です。

**ワークロード ID** の横にあるスイッチを使用して、ポリシーフォームを開きます。アカウントに保存された ID がある場合、スイッチはオンの状態で開始され、保存後もオンのままになります。ID がないアカウントの場合、スイッチはオフの状態で開始されます。組織の場合、このセクションは **SCIM プロビジョニング** の下に表示されます。フォームを非表示にしても下書きは保持され、ワークロード認証は無効になりません。保存された ID カードとセットアップドキュメントへのリンクは表示されたままになります。各カードには、ID の名前、発行者および JWKS URL、オーディエンス、正確な JSON クレーム、アカウント全体のスコープ、作成時刻が表示されます。カード上のアクションを使用して ID を削除します。

以下のフィールドを入力するには **カスタムプロバイダー** を選択するか、組織のスラッグと数値の組織 ID およびアプリケーション ID から生成するには **Fly.io Machines** を選択します。Fly テンプレートでは、生成された発行者、JWKS URL、およびクレームを **詳細設定** で編集可能です。テンプレートまたはヘルパー値を変更しても、手動で編集したフィールドは保持されます。発行者、JWKS URL、またはクレームがテンプレートを上書きする場合、Tuist は **詳細設定** を展開し、警告を表示して、保存されるポリシーを確認できるようにします。Fly ヘルパーを使用せずに続行するには、**カスタムプロバイダー** に戻ります。テンプレートは設定を入力するだけで、Tuist がトークンを検証する方法は変更しません。

| フィールド | 説明 |
| --- | --- |
| 名前 | ポリシーを識別するためのラベル。アカウント内で一意である必要があります。 |
| 発行者 URL | トークンの `iss` クレーム。末尾のスラッシュを含め、完全に一致する必要があります。 |
| JWKS URL | プロバイダーの署名キーの HTTPS URL。Tuist はこの URL を直接使用し、プロバイダーの OpenID Connect 検出ドキュメントを読み取らないため、`jwks_uri` をプロバイダーのドキュメントまたは `<issuer>/.well-known/openid-configuration` からコピーしてください。 |
| オーディエンス | トークンが発行されるべきオーディエンス。デフォルトは `tuist` です。トークンの `aud` はこれと等しいか、`aud` がリストの場合はこれを含んでいる必要があります。他のサービス向けに発行されたトークンがここで再利用されないよう、Tuist だけが受け入れる値を使用してください。 |
| クレーム | トークンに含まれる必要がある 1〜10 個のクレームを持つ JSON オブジェクト。例: `{"sub": "system:serviceaccount:ci:builder"}`。JSON 入力は 8 KiB に制限されています。値は文字列、符号付き 64 ビット整数、またはブール値である必要があり、型も含めて完全に一致する必要があります。`"123"` は `123` と一致しません。ネストされたオブジェクト、リスト、および `iss`、`aud`、`exp`、`nbf`、`iat`、`jti` などの時間やトークンのクレームは許可されません。 |

各ポリシーは、個別のプロジェクトを選択することなく、**アカウントが所有する現在および将来のすべてのプロジェクト** への CI アクセスを付与します。最初のプロジェクトを作成する前に ID を構成できます。これはアカウント管理や他のアカウントへのアクセスを付与するものではありません。

一致するクレームを持つトークンを取得できるすべてのワークロードは、それらのすべてのプロジェクトにアクセスできるため、プロバイダーが保証し、誰も再利用できないクレームを選択してください。削除後に名前変更や再登録が可能な名前よりも、安定した数値 ID を優先してください。

> [!WARNING]
> 共有アイデンティティプロバイダーでは、ポリシーを組織またはテナント **および** 対象のアプリケーション、プロジェクト、またはサービスアカウントにバインドしてください。`main` のようなブランチ名、`production` のような環境、または一般的なロールだけではアイデンティティの境界にはなりません。別のテナントが同じ値を持つトークンを取得する可能性があります。例えば、GitLab.com のポリシーには、`ref` だけでなく、対象プロジェクトの安定した `project_id` を含める必要があります。一致するトークンはキャッシュ書き込みを含むアカウント全体の CI アクセスを付与するため、無関係なワークロードを信頼するポリシーはキャッシュポイズニングを許容する可能性があります。

Tuist は、発行者、オーディエンス、有効期限、not-before 時間（最大 60 秒の時計ずれあり）、およびすべてのクレームを確認した後、トークンに署名したキーを独自の JWKS URL が保持しているポリシーに対してのみアクセスを付与します。発行される 1 時間の CI トークンはアカウント全体を対象とし、プロジェクト ID のスナップショットではありません。発行後にアカウントで作成または転送されたプロジェクトも含まれます。プロジェクトの承認には依然として現在のアカウント所有者権限が必要であるため、プロジェクトを外部に転送すると、そのアカウントのトークン下でのアクセスは削除されます。

#### ワークロードの認証 {#authenticate-a-workload}

1. ポリシーのオーディエンスを使用して、プロバイダーから ID トークンをリクエストします。
2. `TUIST_OIDC_TOKEN` をそのトークンに設定し、`TUIST_OIDC_ACCOUNT` をプロジェクトを所有する Tuist アカウントのハンドルに設定します。アカウントはすべてのトラストポリシー交換に必要です。これは検索先を選択するだけで、それ自体では何も付与しません。
3. `tuist auth login` を実行します。Elixir プロジェクトの場合、代わりに `mix tuist.login` を使用するか、`TUIST_TOKEN` または有効な保存済み資格情報がない場合に Elixir 統合が自動的にトークンを交換するようにします。

結果として得られる Tuist アクセストークンは `ci` スコープグループのみを持ち、選択されたアカウントが所有する現在および将来のすべてのプロジェクトをカバーします。アカウント内の 20 を超えるポリシーが同じトークンに一致する場合、または 2 つを超える異なる JWKS URL を使用する場合、交換は失敗します。

Tuist はこれらのセッションを更新しません。アクセストークンは 1 時間後に有効期限切れになり、更新トークンはありません。プロバイダーの ID トークンはしばしば数分間しか有効でないため、古い `TUIST_OIDC_TOKEN` を保持することは更新戦略ではありません。1 時間以上実行されるジョブの場合、Tuist セッションの有効期限が切れる前に新しい ID トークンをリクエストして再度ログインしてください。ポリシーを削除すると新しい交換は停止しますが、すでに発行されたアクセストークンは有効期限が切れるまで有効です。

Tuist は、専用でサイズ制限のあるキャッシュにおいて、成功したフェッチ後、プロバイダーの署名キーを最大 15 分間キャッシュします。エントリはより早く削除され、再度フェッチされる場合があります。失敗したフェッチはキャッシュされません。プロバイダーがキーを回転させる場合、少なくとも 15 分前に新しいキーを JWKS で公開する必要があります。キャッシュされたセットにないキーで署名されたトークンは、キャッシュの有効期限が切れるまで拒否されるためです。キー ID (`kid`) のないトークンは、JWKS に単一の適格な署名キーが含まれている場合にのみ受け入れられます。JWKS にキー ID が存在する場合、それは最大 256 バイトの文字列である必要があります。

> [!NOTE]
> `TUIST_OIDC_TOKEN` は汎用的なトークン入力であり、サーバーの信頼を bypass する方法ではありません。これは CI プロバイダーの検出よりも優先され、サーバーは組み込みプロバイダーと一致するトラストポリシーを持つ ID のみを受け入れます。Tuist 資格情報を期待する `TUIST_TOKEN` に ID トークンを入れないでください。

交換が失敗した場合、ポリシー内の発行者、オーディエンス、およびすべてのクレームがトークンと完全に一致していること、JWKS URL がトークンに署名したキーを提供していること、ポリシーが削除されていないこと、および `TUIST_OIDC_ACCOUNT` がプロジェクトを所有するアカウントを指していることを確認してください。どの ID が信頼されているかを公開しないようにするため、Tuist はこれらのすべてのケースで同じエラーを返します。

### Fly.io Machines {#flyio-machines}

[Fly.io は OIDC ワークロード ID をサポートしています](https://docs.fly.io/reference/openid-connect/)。Machine は、Fly API トークンや長寿命の Tuist シークレットなしで、ローカルの `/.fly/api` Unix ソケットから短命の署名付き ID トークンをリクエストできます。Fly トークンはソースリポジトリではなく組織とアプリケーションを識別するため、GitHub リポジトリを接続する代わりにトラストポリシーを使用してください。

1. Fly Machine 内で発行された ID トークンから、発行者 (`iss`)、組織 ID (`org_id`)、およびアプリケーション ID (`app_id`) を取得します。発行者は `https://oidc.fly.io/<organization-slug>` です。組織名やアプリ名ではなく、数値 ID を使用してください。
2. **Fly.io Machines** テンプレートを使用して [トラストポリシーを作成](#create-a-trust-policy) し、組織のスラッグと両方の数値 ID を入力します。これにより以下の値が入力され、ID は文字列として保持されます。**カスタムプロバイダー** を使用して手動で入力することもできます。クレーム内の ID の周りに引用符を保持してください。

   | フィールド | 値 |
   | --- | --- |
   | 発行者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | オーディエンス | `tuist` |
   | クレーム | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Machine 内で、`TUIST_OIDC_ACCOUNT` をプロジェクトを所有する Tuist アカウントのハンドル（Fly 組織のスラッグではない）に設定し、オーディエンス `tuist` でトークンをリクエストして、`TUIST_OIDC_TOKEN` を使用して `tuist auth login` に渡します。

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

初期設定では、トークンをエクスポートした後、アンセットする前に、ローカルで ID フィールドのみを検査できます。これにより構成用のクレームをデコードします。Tuist は認証中に署名を個別に検証します。

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

トークン自体を出力したりコミットしたりしないでください。承認された Fly アプリ内のすべての Machine は、Tuist アカウントの現在および将来のすべてのプロジェクトに対して認証できます。追加のアプリごとに個別のポリシーを作成してください。Fly の ID トークンは約 10 分で期限切れになるため、長時間実行される Machine では、1 時間の Tuist セッションが期限切れになる前に新しいトークンをリクエストして `tuist auth login` を再度実行してください。

### OIDC トークンスコープ {#oidc-token-scopes}

OIDC トークンには `ci` スコープグループが付与されます。GitHub Actions、CircleCI、Bitrise の場合、これによりリポジトリに接続されているすべてのプロジェクトへのアクセスが可能になります。ワークロード ID トラストポリシーの場合、これにより選択したアカウントが所有する現在および将来のすべてのプロジェクトへのアクセスが可能になりますが、プロジェクトの作成、プロジェクト管理、ランナー管理、またはアカウントメンバー管理は付与されません。`ci` スコープに含まれる内容の詳細については、[スコープグループ](#scope-groups) を参照してください。

> [!TIP]
> **セキュリティ上の利点**
>
> OIDC 認証は長寿命のトークンよりも安全です。その理由は次のとおりです。
> - 回転や管理が必要なシークレットがない
> - トークンは短命である
> - 認証はリポジトリ ID または明示的に承認されたワークロード ID に紐付けられている


## Gradle プラグイン認証 {#gradle-plugin-authentication}

Gradle プラグインは Tuist CLI の認証状態を使用し、個別のログインフローを定義しません。CLI で一度認証すると、プラグインはその資格情報を再利用します。

`project` や `url` を含むプロジェクトおよびサーバー構成には、標準の <.localized_link href="/references/tuist-toml">tuist.toml リファレンス</.localized_link> を使用してください。

ローカルで使用するには、次を実行します。

```bash
tuist auth login
```

CI の場合は、次のいずれかを使用します。

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 認証</.localized_link>（利用可能な場合に推奨）
- <.localized_link href="/guides/server/authentication#continuous-integration">アカウントトークン認証</.localized_link>（`TUIST_TOKEN` を経由）

セルフホスト型の Tuist サーバーの場合は、`tuist.toml` でサーバー URL を定義し（例：`url = "https://tuist.your-company.com"`）、標準のログインフローを実行します。URL はプラグインで使用される同じ構成ファイルから解決されます。

認証が構成された後、Gradle のキャッシュコマンドとタスクを通常どおり実行します。

## アカウントトークン {#account-tokens}

OIDC をサポートしない CI 環境の場合、または権限を細かく制御する必要がある場合は、アカウントトークンを使用できます。アカウントトークンを使用すると、トークンがアクセスできるスコープとプロジェクトを正確に指定できます。

### アカウントトークンの作成 {#creating-an-account-token}

アカウントトークンを作成する最も簡単な方法は、ダッシュボードからです。

1. Tuist ダッシュボードで組織を開きます。
2. **設定** > **トークン** に移動します。
3. **トークンを生成** を選択します。
4. 名前、オプションの有効期限、プロジェクトアクセス、およびトークンに必要なスコープを選択します。
5. ダイアログを閉じる前に、生成されたトークン値をコピーします。トークン値は一度だけ表示されます。

CLI からアカウントトークンを作成することもできます。これはスクリプトや自動化に役立ちます。

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> `account-handle` を、トークンにアクセスさせたいプロジェクトを所有するアカウントのハンドルに置き換えます。これは個人アカウントではなく、組織アカウントでも構いません。

コマンドは次のオプションを受け入れます。

| オプション | 説明 |
| --- | --- |
| `--scopes` | 必須。トークンに付与するスコープのカンマ区切りリスト。 |
| `--name` | 必須。トークンの一意の識別子（1〜32 文字、英数字、ハイフン、アンダースコアのみ）。 |
| `--expires` | オプション。トークンの有効期限。形式は `30d`（日）、`6m`（月）、または `1y`（年）などを使用します。指定しない場合、トークンは無期限です。 |
| `--projects` | トークンを特定のプロジェクトハンドルに制限します。指定しない場合、トークンはすべてのプロジェクトにアクセスできます。 |

### 利用可能なスコープ {#available-scopes}

| スコープ | 説明 |
| --- | --- |
| `account:cache:read` | アカウントスコープのキャッシュされたバイナリをダウンロード |
| `account:cache:write` | アカウントスコープのキャッシュされたバイナリをアップロード |
| `account:members:read` | アカウントメンバーを読み取る |
| `account:members:write` | アカウントメンバーを管理する |
| `account:registry:read` | Swift パッケージレジストリから読み取る |
| `account:registry:write` | Swift パッケージレジストリに公開する |
| `account:runners:read` | ランナーのジョブ、ワークフロー、プロファイル、およびボリュームを読み取る |
| `account:runners:write` | ランナーのプロファイルを管理し、ランナーのボリュームをクリアする |
| `project:previews:read` | プレビューをダウンロード |
| `project:previews:write` | プレビューをアップロード |
| `project:admin:read` | プロジェクトとその設定を読み取る |
| `project:admin:write` | プロジェクトを作成、更新、削除します。プロジェクトを作成するには、すべてのプロジェクトにアクセスできるトークンが必要です |
| `project:cache:read` | キャッシュされたバイナリをダウンロード |
| `project:cache:write` | キャッシュされたバイナリをアップロード |
| `project:bundles:read` | バンドルを表示 |
| `project:bundles:write` | バンドルをアップロード |
| `project:tests:read` | テスト結果を読み取る |
| `project:tests:write` | テスト結果をアップロード |
| `project:builds:read` | ビルド分析を読み取る |
| `project:builds:write` | ビルド分析をアップロード |
| `project:runs:read` | コマンド実行を読み取る |
| `project:runs:write` | コマンド実行を作成および更新 |

### スコープグループ {#scope-groups}

スコープグループは、単一の識別子で複数の関連するスコープを付与する便利な方法を提供します。スコープグループを使用すると、含まれる個々のスコープが自動的に展開されます。

| スコープグループ | 含まれるスコープ |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 継続的インテグレーション {#continuous-integration}

OIDC をサポートしない CI 環境の場合、`ci` スコープグループを使用してアカウントトークンを作成し、CI ワークフローを認証します。ダッシュボードでは、トークンを生成する際に **CI** プリセットを選択します。

CLI から同じトークンを作成することもできます。

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

これにより、一般的な CI 操作（キャッシュ、プレビュー、バンドル、テスト、ビルド、実行）に必要なすべてのスコープを持つトークンが作成されます。生成されたトークンを CI 環境のシークレットとして保存し、`TUIST_TOKEN` 環境変数として設定します。

### アカウントトークンの管理 {#managing-account-tokens}

アカウントダッシュボードで **設定** > **トークン** を開き、アカウントトークンを表示し、トークンのスコープとプロジェクトアクセスを確認し、ローテーション中にトークンを取り消します。

アカウントのすべてのトークンを一覧表示するには:

```bash
tuist account tokens list account-handle
```

名前でトークンを取り消すには:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### アカウントトークンの使用 {#using-account-tokens}

アカウントトークンは環境変数 `TUIST_TOKEN` として定義されることを想定しています。

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **アカウントトークンを使用するタイミング**
>
> 次のような場合にアカウントトークンを使用してください。
> - OIDC をサポートしない CI 環境での認証
> - トークンが実行できる操作に対する細かな制御
> - アカウント内の複数のプロジェクトにアクセスできるトークン
> - 自動的に期限切れになる時間制限付きトークン
