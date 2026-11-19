---
{
  "title": "認証",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "CLI から Tuist サーバーへの認証方法を学びます。"
}
---
# 認証 {#authentication}

サーバーと通信するには、CLI は [Bearer 認証](https://swagger.io/docs/specification/authentication/bearer-authentication/) を使用してリクエストを認証する必要があります。CLI は、ユーザーとして、アカウントとして、または OIDC トークンを使用して認証することをサポートしています。

## ユーザーとして {#as-a-user}

マシン上でローカルに CLI を使用する場合は、ユーザーとして認証することをお勧めします。ユーザーとして認証するには、次のコマンドを実行する必要があります。

```bash
tuist auth login
```

このコマンドを実行すると、Web ベースの認証フローが始まります。認証が完了すると、CLI は長期有効なリフレッシュトークンと短期有効なアクセストークンを `~/.config/tuist/credentials` に保存します。ディレクトリ内の各ファイルは、認証を行ったドメインを表しており、デフォルトでは `tuist.dev.json` になります。このディレクトリに保存される情報は機密性が高いので、**安全に保管してください**。

CLI は、サーバーへのリクエスト時に自動的に資格情報を参照します。アクセストークンの有効期限が切れている場合、CLI はリフレッシュトークンを使用して新しいアクセストークンを取得します。

> [!NOTE]
> 組織でシングルサインオンを使用している場合は、ブラウザでエンタープライズログインオプションを選択し、勤務先のメールアドレスを入力してください。Tuist は、既存の組織メンバーシップまたは <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">検証済みのログイン用メールドメイン</.localized_link> からプロバイダーを検出できます。

## OIDC トークン {#oidc-tokens}

OpenID Connect (OIDC) をサポートする CI 環境の場合、Tuist は長期間有効なシークレットを管理する必要なく、自動的に認証できます。サポートされている CI 環境で実行されると、CLI は OIDC トークンプロバイダーを自動的に検出し、CI が提供したトークンを Tuist のアクセストークンと交換します。

### サポートされているプロバイダー {#supported-ci-providers}

Tuist は以下の CI プロバイダーを認識し、リポジトリ接続を通じてそのトークンをプロジェクトにマッピングします。

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) Orb は、Tuist アカウントに接続した Amp ワークスペースを通じて認証され、[Claude Code セッション](#claude-code-sessions) は、Tuist Sandboxes で実行するために接続した Claude Code 環境を通じて認証されます。

OpenID Connect トークンを発行する他のあらゆる ID プロバイダーは、アカウント内の現在および将来のすべてのプロジェクトに対して一度だけ設定する [ワークロード ID 信頼ポリシー](#workload-identity-trust-policies) を介して認証できます。例えば [Fly.io Machines](#flyio-machines) などです。

### OIDC 認証の設定 {#setting-up-oidc-authentication}

GitHub Actions、CircleCI、Bitrise の場合：

1. **リポジトリを Tuist に接続**：<.localized_link href="/guides/integrations/gitforge/github">GitHub 統合ガイド</.localized_link> に従って、GitHub リポジトリを Tuist プロジェクトに接続します。

2. **ID トークンを付与**：GitHub Actions では、ジョブに `permissions: id-token: write` を付与します。CircleCI および Bitrise では、プロジェクトで OIDC を有効にします。Tuist 4.218.0 以降では、CLI がサインインしておらず、`TUIST_TOKEN` も設定されていない場合、CI 環境を検出して最初のリクエストで ID トークンを交換するため、ログイン手順は不要です。それ以前のバージョンでは最初に `tuist auth login` が必要であり、明示的にサインインして、交換が拒否された場合に早期に失敗させるために引き続き実行できます。

プロバイダー固有の設定例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

### Amp Orbs {#amp-orbs}

[Amp](https://ampcode.com) Orb は、その Amp ワークスペースを識別する OIDC トークンを発行できます。ワークスペースを Tuist アカウントに一度接続すると、そのワークスペースの任意の Orb 内にある Tuist CLI と `tuist_ex` Mix タスクは、保存されたトークンやログイン手順なしで自動的にサインインします。

1. ID の確認：Orb 内で実行されるワークスペースのスレッドで、`echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID` を実行します。
2. Tuist アカウントで **Settings → Integrations** を開き、Amp カードで **Connect workspace** を選択して、ワークスペース ID を貼り付けます。1 つの Amp プロジェクトの Orb のみを許可するには、そのプロジェクト ID も貼り付けてください。アカウント管理者または所有者である必要があります。
3. ワークスペースの Orb で Tuist を使用します。サインインしていない場合、CLI または Mix タスクは Orb を検出し、`amp orb id-token --audience https://tuist.dev` でトークンを発行して、それを Tuist セッションと交換します。`tuist auth login` および `mix tuist.login` も同じ交換を明示的に行います。

[Amp の OIDC ガイド](https://ampcode.com/manual/orbs/oidc) の信頼構成と同様に、Tuist はすべてのトークンで Amp の署名を検証し、オーディエンスが `https://tuist.dev` であり、`token_use` が `exchanged` であり、`workspace_id` が接続されたワークスペースと一致し、プロジェクトに限定された接続の場合は `project_id` がそのプロジェクトと一致する場合のみ、トークンを受け入れます。`sub` は、これらのクレームと同じワークスペース名（プロジェクト接続の場合は同じプロジェクト名）を指定する必要があります：`workspace:<workspace-id>:project:<project-id>:…`。これは `amp orb id-token` がデフォルトで発行します。

接続によって許可されたすべての Orb は、キャッシュのアップロードを含め、アカウントが所有する現在および将来のすべてのプロジェクトに対する CI アクセス権限を取得します。また、`account:sandboxes:write` スコープも取得するため、アカウントのメンバーと同様に <.localized_link href="/guides/features/sandboxes">サンドボックス</.localized_link> を作成し、そこでコマンドを実行できます。例えば、Linux Orb から macOS サンドボックスでビルドするなどです。そのアクセス権限を信頼できるメンバーを持つワークスペースのみを接続してください。ID を慎重に確認してください。Tuist は、あなたが接続しようとしているワークスペースに所属していることを確認できません。ワークスペースが複数の Tuist アカウントに接続されている場合、Orb はサインイン先のアカウントを指定するために `TUIST_OIDC_ACCOUNT` を設定する必要があります。Amp プロジェクトの環境変数でこれを設定することで、サインインをあなたのアカウントに固定することもできます。ワークスペース外のスレッドにはワークスペース ID がなく、接続を使用できません。Amp カードからワークスペースを切断すると、新しいサインインを停止できます。すでに発行されたセッションは、1 時間後に有効期限が切れるまで有効です。セッションにはリフレッシュトークンは必要ありません。有効期限が近づくと、Orb 内の CLI が新しい Amp トークンを発行して再度交換するため、ワークスペースが接続されている限り、長時間実行される Orb はサインイン状態を維持します。

ワークスペースを接続する前に作成した Amp 発行元用の信頼ポリシーは、`TUIST_OIDC_ACCOUNT` を設定しても引き続き機能します。

### Claude Code セッション {#claude-code-sessions}

セルフホスト環境内の各 Claude Code クラウドセッションには、Anthropic が署名した ID トークン（`CLAUDE_CODE_SESSION_ACCESS_TOKEN`）が含まれています。<.localized_link href="/guides/features/sandboxes/claude#claude-code">Tuist Sandboxes で実行するために接続</.localized_link>した環境では、Tuist はこれを `TUIST_OIDC_TOKEN` としてセッションに渡すため、Tuist CLI と `tuist_ex` Mix タスクは自動的にサインインします。

Tuist は Anthropic の署名を検証し、トークンがセッショントークン（`ccr:role` が `session_worker`）であり、そのオーディエンスで指定された環境が Tuist アカウントに接続されて有効になっている場合にのみ、そのトークンを受け入れます。接続された環境のすべてのセッションは、キャッシュのアップロードを含め、アカウントが所有する現在および将来のすべてのプロジェクトに対する CI アクセス権限を取得し、アカウントのメンバーと同様にアカウントのサンドボックスを作成して使用できます。したがって、Claude 組織が環境の使用を許可している人は誰でも、あなたのキャッシュに公開し、ビルド用の Mac などサンドボックスを開始できます。セッションの Tuist セッションは、1 時間後または ID トークンの有効期限切れのいずれか早い方で失効します。トークンはセッション開始時に使用されたもので、デフォルトでは 4 時間有効です。そのため、より長いセッションの場合、次のメッセージで新しいランナーで再開されるまで Tuist アクセスは失われます。新しいサインインを停止するには、環境を切断または無効にしてください。

### ワークロード ID 信頼ポリシー {#workload-identity-trust-policies}

信頼ポリシーを使用すると、デプロイメントプラットフォーム、Kubernetes クラスタ、またはセルフマネージド CI システムなど、別の ID プロバイダからのワークロードが、長寿命の Tuist シークレットなしでプロジェクトにアクセスできるようになります。プロバイダは以下の条件を満たす必要があります。

- パブリックアドレスで HTTPS 経由で到達可能であること。Tuist はリダイレクトに従わず、プライベートまたは内部ネットワークアドレスには接続しません。これはセルフホスト型 Tuist サーバーからの接続も含みます。
- 非対称鍵（例えば `RS256` や `ES256`）で署名された JWT を発行すること。署名されていないトークンや共有シークレット（`HS256` など）で署名されたトークンは拒否されます。
- 署名鍵を JSON Web Key Set (JWKS) として固定の HTTPS URL で公開すること。レスポンスは最大 64 KiB で、最大 20 個の鍵を含む必要があります。
- すべてのトークンに有効期限（`exp`）を含めること。

GitHub Actions、CircleCI、および Bitrise の発行元は、上記のリポジトリベースのフロー用に予約されており、信頼ポリシーでは使用できません。

> [!NOTE]
> セルフホスト型のロールアウトの場合、ワークロード ID を構成したりジョブを移行したりする前に、データベースマイグレーションを適用し、稼働中のすべての Tuist サーバーレプリカをアップグレードしてください。その後、CLI または Elixir 統合を `TUIST_OIDC_TOKEN` と `TUIST_OIDC_ACCOUNT` をサポートするバージョンにアップグレードしてください。既存の GitHub Actions、CircleCI、および Bitrise ジョブはリポジトリベースの認証を引き続き使用し、アカウントハンドルは必要ありません。本番ジョブを切り替える前に、意図したワークロードで短期間のトークン交換とキャッシュ操作を検証してください。新しい交換を停止するには、ポリシーを削除してください。すでに発行された Tuist アクセストークンが失効するまで最大 1 時間かかります。ポリシーを削除しても、これらのトークンは直ちに取り消されません。

#### ポリシーの作成 {#create-a-trust-policy}

Tuist ダッシュボードで、アカウントの **設定** > **認証** を開き、**ワークロード ID** セクションを見つけます。あなたはアカウント管理者（または個人アカウントの所有者）である必要があります。各アカウントには最大 20 のポリシーを設定できます。アカウント全体の CI アクセス権限のために ID を一度設定します。プロジェクトの選択は不要です。

**ワークロード ID** の横にあるスイッチを使用してポリシーフォームを開きます。アカウントに保存された ID がある場合、スイッチはオン状態で始まり、保存後もオンのままです。ID がないアカウントの場合、スイッチはオフ状態で始まります。組織の場合、このセクションは **SCIM プロビジョニング** の下に表示されます。フォームを非表示にしても下書きは保存され、ワークロード認証は無効になりません。保存された ID カードとセットアップドキュメントへのリンクは表示されたままです。各カードには、ID の名前、発行元と JWKS の URL、オーディエンス、正確な JSON クレーム、アカウント全体のスコープ、作成時刻が表示されます。カード上のアクションを使用して ID を削除します。

以下のフィールドを入力するには **カスタムプロバイダ** を選択するか、組織のスラッグと数値の組織 ID およびアプリケーション ID から生成するには **Fly.io Machines** を選択します。Fly テンプレートは、生成された発行元、JWKS URL、およびクレームを **詳細設定** で編集可能な状態に保ちます。テンプレートまたはヘルパー値を変更しても、手動で編集したフィールドは保持されます。発行元、JWKS URL、またはクレームがテンプレートを上書きする場合、Tuist は **詳細設定** を展開し、警告を表示して、保存されるポリシーを確認できるようにします。Fly ヘルパーなしで続行するには、**カスタムプロバイダ** に戻ってください。テンプレートは設定を入力するだけで、Tuist がトークンを検証する方法は変更しません。

| フィールド | 説明 |
| --- | --- |
| 名前 | ポリシーを識別するためのラベル。アカウント内で一意である必要があります。 |
| 発行元 URL | トークンの `iss` クレーム。末尾のスラッシュを含め、完全に一致する必要があります。 |
| JWKS URL | プロバイダの署名鍵の HTTPS URL。Tuist はこの URL を直接使用し、プロバイダの OpenID Connect ディスカバリードキュメントを読み取らないため、プロバイダのドキュメントまたは `<issuer>/.well-known/openid-configuration` から `jwks_uri` をコピーしてください。 |
| オーディエンス | トークンが発行されるべきオーディエンス。デフォルトは `tuist` です。トークンの `aud` はこれと等しいか、`aud` がリストの場合はこれを含んでいる必要があります。他のサービス用に発行されたトークンがここで再利用されないよう、Tuist だけが受け入れる値を使用してください。 |
| クレーム | トークンが含まなければならない 1〜10 個のクレームを持つ JSON オブジェクト。例えば `{"sub": "system:serviceaccount:ci:builder"}` です。JSON 入力は最大 8 KiB に制限されます。値は文字列、符号付き 64 ビット整数、またはブール値である必要があり、型を含めて完全に一致する必要があります。`"123"` は `123` と一致しません。ネストされたオブジェクト、リスト、および `iss`、`aud`、`exp`、`nbf`、`iat`、`jti` などの時間またはトークン関連のクレームは許可されません。 |

各ポリシーは、個別のプロジェクトを選択することなく、**アカウントが所有する現在および将来のすべてのプロジェクト**に対する CI アクセス権限を付与します。最初のプロジェクトを作成する前に ID を構成できます。これにより、アカウント管理権限や他のアカウントへのアクセス権限は付与されません。

一致するクレームを持つトークンを取得できるすべてのワークロードは、それらのすべてのプロジェクトにアクセスできるため、プロバイダが保証し、誰も再利用できないクレームを選択してください。削除後に名前変更や再登録が可能な名前よりも、安定した数値 ID を優先してください。

> [!WARNING]
> 共有 ID プロバイダでは、ポリシーを組織またはテナント **と**、対象のアプリケーション、プロジェクト、またはサービスアカウントにバインドしてください。`main` などのブランチ名、`production` などの環境、または一般的なロールだけでは ID の境界にはなりません。他のテナントが同じ値を持つトークンを取得する可能性があるためです。例えば、GitLab.com のポリシーは、`ref` だけでなく、対象プロジェクトの安定した `project_id` を含める必要があります。一致するトークンはキャッシュ書き込みを含むアカウント全体の CI アクセス権限を付与するため、無関係なワークロードを信頼するポリシーはキャッシュポイズニングを許可する可能性があります。

Tuist は、発行元、オーディエンス、有効期限、not-before 時刻（最大 60 秒の時計ずれまで）、およびすべてのクレームを確認した後、トークンに署名した鍵を独自の JWKS URL で保持しているポリシーに対してのみアクセスを付与します。発行される 1 時間有効の CI トークンはアカウント全体に適用され、プロジェクト ID のスナップショットではありません。発行後に作成されたプロジェクトやアカウントに転送されたプロジェクトも含まれます。プロジェクトの認可には引き続き現在のアカウント所有権が必要であるため、プロジェクトをアカウント外に転送すると、そのアカウントのトークンによるアクセス権は失われます。

#### ワークロードの認証 {#authenticate-a-workload}

1. プロバイダから、ポリシーのオーディエンスを持つ ID トークンをリクエストします。
2. `TUIST_OIDC_TOKEN` にそのトークンを設定し、`TUIST_OIDC_ACCOUNT` にプロジェクトを所有する Tuist アカウントのハンドルを設定します。すべての信頼ポリシー交換にはアカウントが必要です。これは検索場所を選択するだけで、それ自体では何も付与しません。
3. Tuist を実行します。`TUIST_TOKEN` または有効な保存済み認証情報が利用できない場合、CLI と Elixir 統合は自動的にトークンを交換します。`tuist auth login` および `mix tuist.login` も明示的に同じ交換を行います。

結果として得られる Tuist アクセストークンは `ci` スコープグループのみを持ち、選択したアカウントが所有する現在および将来のすべてのプロジェクトをカバーします。アカウント内の 20 を超えるポリシーが同じトークンに一致する場合、または 2 つを超える異なる JWKS URL を使用する場合、交換は失敗します。

Tuist はこれらのセッションを更新しません。アクセストークンは 1 時間後に有効期限が切れ、リフレッシュトークンはありません。プロバイダの ID トークンの有効期間は数分間であることが多いため、古い `TUIST_OIDC_TOKEN` を保持することは更新戦略にはなりません。1 時間以上実行されるジョブの場合、Tuist セッションの有効期限が切れる前に新しい ID トークンをリクエストして再度ログインしてください。ポリシーを削除すると新しい交換は停止しますが、すでに発行されたアクセストークンは有効期限が切れるまで有効です。

Tuist は、専用のサイズ制限付きキャッシュで、プロバイダの署名鍵を正常に取得してから最大 15 分間キャッシュします。エントリはより早く削除され、再取得される場合があります。失敗した取得はキャッシュされません。プロバイダが鍵を回転させる場合、新しい鍵を使用してトークンに署名する少なくとも 15 分前に JWKS で公開する必要があります。キャッシュされたセットに含まれていない鍵で署名されたトークンは、キャッシュの有効期限が切れるまで拒否されるためです。鍵 ID (`kid`) がないトークンは、JWKS に単一の適格な署名鍵が含まれている場合にのみ受け入れられます。JWKS に鍵 ID が存在する場合、それは最大 256 バイトの文字列である必要があります。

> [!NOTE]
> `TUIST_OIDC_TOKEN` は汎用的なトークン入力であり、サーバー信頼を回避する方法ではありません。CI プロバイダ検出よりも優先されますが、サーバーは組み込みプロバイダと一致する信頼ポリシーを持つ ID のみを受け入れます。Tuist 認証情報を想定する `TUIST_TOKEN` に ID トークンを入れないでください。

交換が失敗した場合、ポリシー内の発行元、オーディエンス、およびすべてのクレームがトークンと完全に一致していること、JWKS URL がトークンに署名した鍵を提供していること、ポリシーが削除されていないこと、および `TUIST_OIDC_ACCOUNT` がプロジェクトを所有するアカウントを指していることを確認してください。どの ID が信頼されているかを露呈しないよう、Tuist はこれらのすべてのケースで同じエラーを返します。

### Fly.io Machines {#flyio-machines}

[Fly.io は OIDC ワークロード ID をサポートしています](https://docs.fly.io/reference/openid-connect/)。Machine は、Fly API トークンや長寿命の Tuist シークレットなしで、ローカルの `/.fly/api` Unix ソケットから短命の署名付き ID トークンをリクエストできます。Fly トークンはソースリポジトリではなく組織とアプリケーションを識別するため、GitHub リポジトリを接続する代わりに信頼ポリシーを使用してください。

1. Fly Machine 内で発行された ID トークンから、発行元 (`iss`)、組織 ID (`org_id`)、およびアプリケーション ID (`app_id`) を取得します。発行元は `https://oidc.fly.io/<organization-slug>` です。組織名やアプリ名ではなく、数値 ID を使用してください。
2. **Fly.io Machines** テンプレートを使用して [信頼ポリシーを作成し](#create-a-trust-policy)、組織スラッグと両方の数値 ID を入力します。これにより以下の値が入力され、ID は文字列として保持されます。**カスタムプロバイダ** を使用して手動で入力することもできます。その場合、クレーム内の ID の引用符を保持してください。

   | フィールド | 値 |
   | --- | --- |
   | 発行元 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | オーディエンス | `tuist` |
   | クレーム | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Machine 内で、`TUIST_OIDC_ACCOUNT` をプロジェクトを所有する Tuist アカウントのハンドル（Fly 組織スラッグではない）に設定し、オーディエンス `tuist` でトークンをリクエストして、`TUIST_OIDC_TOKEN` を使用して `tuist auth login` に渡します。

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

初期設定では、トークンをエクスポートした後、アンセットする前に、ローカルで ID フィールドのみを検査できます。これにより構成用のクレームをデコードします。Tuist は認証中に署名を別途検証します。

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

トークン自体を印刷したりコミットしたりしないでください。承認された Fly アプリ内のすべての Machine は、Tuist アカウント内の現在および将来のすべてのプロジェクトに対して認証できます。追加のアプリごとに個別のポリシーを作成してください。Fly ID トークンは約 10 分後に有効期限が切れるため、長時間実行される Machine では、1 時間の Tuist セッションの有効期限が切れる前に新しいトークンをリクエストして `tuist auth login` を再度実行してください。

### OIDC トークンスコープ {#oidc-token-scopes}

OIDC トークンには `ci` スコープグループが付与されます。GitHub Actions、CircleCI、Bitrise の場合、これはリポジトリに接続されたすべてのプロジェクトへのアクセスを提供します。接続された Amp ワークスペース、接続された Claude Code 環境、およびワークロード ID 信頼ポリシーの場合、これはプロジェクト作成、プロジェクト管理、ランナー管理、またはアカウントメンバー管理を付与することなく、選択したアカウントが所有する現在および将来のすべてのプロジェクトへのアクセスを提供します。`ci` スコープに含まれる内容の詳細については、[スコープグループ](#scope-groups) を参照してください。

> [!TIP]
> **セキュリティ上の利点**
>
> OIDC 認証は長寿命トークンよりも安全です。その理由は次のとおりです。
> - 回転や管理が必要なシークレットがない
> - トークンの有効期間が短い
> - 認証がリポジトリ ID または明示的に承認されたワークロード ID に紐付けられている


## Gradle プラグインの認証 {#gradle-plugin-authentication}

Gradle プラグインは Tuist CLI の認証状態を使用し、独自のログインフローを定義しません。CLI で一度認証すると、プラグインはその認証情報を再利用します。

`project` や `url` を含むプロジェクトおよびサーバーの設定には、標準の <.localized_link href="/references/tuist-toml">tuist.toml リファレンス</.localized_link> を使用してください。

ローカルでの使用では、次を実行します。

```bash
tuist auth login
```

CI では、次のいずれかを使用します。

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 認証</.localized_link>（利用可能な場合に推奨）
- <.localized_link href="/guides/server/authentication#continuous-integration">アカウントトークン認証</.localized_link>（`TUIST_TOKEN` を使用）

セルフホスト型の Tuist サーバーの場合、`tuist.toml` でサーバー URL を定義し（例：`url = "https://tuist.your-company.com"`）、標準のログインフローを実行します。URL はプラグインが使用する同じ設定ファイルから解決されます。

認証を設定した後、Gradle のキャッシュコマンドとタスクを通常どおり実行します。

## アカウントトークン {#account-tokens}

OIDC をサポートしない CI 環境や、権限を細かく制御する必要がある場合は、アカウントトークンを使用できます。アカウントトークンを使用すると、トークンがアクセスできるスコープとプロジェクトを正確に指定できます。

### アカウントトークンの作成 {#creating-an-account-token}

アカウントトークンを作成する最も簡単な方法は、ダッシュボードから行うことです。

1. Tuist ダッシュボードで組織を開きます。
2. **設定** > **トークン** に移動します。
3. **トークンを生成** を選択します。
4. 名前、任意の有効期限、プロジェクトアクセス、およびトークンに必要なスコープを選択します。
5. ダイアログを閉じる前に、生成されたトークンの値をコピーします。トークンの値は一度しか表示されません。

CLI からアカウントトークンを作成することもでき、スクリプトや自動化に役立ちます。

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> `account-handle` を、トークンにアクセスさせたいプロジェクトを所有するアカウントのハンドルに置き換えます。これは個人アカウントではなく、組織アカウントでも構いません。

このコマンドは次のオプションを受け付けます。

| オプション | 説明 |
| --- | --- |
| `--scopes` | 必須。トークンに付与するスコープのスペース区切りリスト。 |
| `--name` | 必須。トークンの一意の識別子（1〜32文字、英数字、ハイフン、アンダースコアのみ）。 |
| `--expires` | 任意。トークンの有効期限。`30d`（日）、`6m`（月）、または `1y`（年）などの形式を使用します。指定しない場合、トークンは無期限です。 |
| `--projects` | トークンを特定のプロジェクトハンドルに制限します。指定しない場合、トークンはすべてのプロジェクトにアクセスできます。 |

### 利用可能なスコープ {#available-scopes}

| スコープ | 説明 |
| --- | --- |
| `account:cache:read` | アカウントスコープのキャッシュ済みバイナリをダウンロード |
| `account:cache:write` | アカウントスコープのキャッシュ済みバイナリをアップロード |
| `account:members:read` | アカウントメンバーを読み取り |
| `account:members:write` | アカウントメンバーを管理 |
| `account:pulse:write` | Sentry SDK からアカウントの Pulse にエラーを送信（トークンを DSN キーとして使用） |
| `account:registry:read` | Swift パッケージレジストリから読み取り |
| `account:registry:write` | Swift パッケージレジストリに公開 |
| `account:runners:read` | ランナーのジョブ、ワークフロー、プロファイル、およびボリュームを読み取り |
| `account:runners:write` | ランナーのプロファイルを管理し、ランナーのボリュームを削除 |
| `account:sandboxes:write` | サンドボックスを作成し、アカウントメンバーと同様にその中でコマンドを実行 |
| `project:previews:read` | プレビューをダウンロード |
| `project:previews:write` | プレビューをアップロード |
| `project:admin:read` | プロジェクトとその設定を読み取り |
| `project:admin:write` | プロジェクトの作成、更新、削除。プロジェクトを作成するには、すべてのプロジェクトにアクセスできるトークンが必要です |
| `project:cache:read` | キャッシュ済みバイナリをダウンロード |
| `project:cache:write` | キャッシュ済みバイナリをアップロード |
| `project:bundles:read` | バンドルを表示 |
| `project:bundles:write` | バンドルをアップロード |
| `project:tests:read` | テスト結果を読み取り |
| `project:tests:write` | テスト結果をアップロード |
| `project:builds:read` | ビルド分析を読み取り |
| `project:builds:write` | ビルド分析をアップロード |
| `project:runs:read` | コマンド実行を読み取り |
| `project:runs:write` | コマンド実行を作成・更新 |

### スコープグループ {#scope-groups}

スコープグループは、単一の識別子で複数の関連するスコープを付与する便利な方法です。スコープグループを使用すると、含まれる個々のスコープが自動的に展開されます。

| スコープグループ | 含まれるスコープ |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 継続的インテグレーション {#continuous-integration}

OIDC をサポートしない CI 環境では、`ci` スコープグループを持つアカウントトークンを作成して、CI ワークフローを認証します。ダッシュボードでは、トークンを生成する際に **CI** プリセットを選択します。

CLI から同じトークンを作成することもできます。

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

これにより、一般的な CI 操作（キャッシュ、プレビュー、バンドル、テスト、ビルド、実行）に必要なすべてのスコープを持つトークンが作成されます。生成されたトークンを CI 環境のシークレットとして保存し、`TUIST_TOKEN` 環境変数として設定します。

### アカウントトークンの管理 {#managing-account-tokens}

アカウントダッシュボードで **設定** > **トークン** を開き、アカウントトークンの表示、トークンのスコープとプロジェクトアクセスの確認、およびローテーション時のトークンの失効を行います。

アカウントのすべてのトークンを一覧表示するには:

```bash
tuist account tokens list account-handle
```

名前でトークンを取り消すには:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### アカウントトークンの使用 {#using-account-tokens}

アカウントトークンは、環境変数 `TUIST_TOKEN` として定義されることが想定されています。

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **アカウントトークンを使用するタイミング**
>
> 次のような場合にアカウントトークンを使用します。
> - OIDC をサポートしない CI 環境での認証
> - トークンが実行できる操作に対する細かな制御
> - アカウント内の複数のプロジェクトにアクセスできるトークン
> - 自動的に期限切れになる時間制限付きトークン
