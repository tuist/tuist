---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | インテグレーション | ガイド | Tuist",
  "description": "Tuist のビルド、テスト、バンドル、プレビューのインサイトを Entire Trails に公開します。"
}
---
# Entire 統合 {#entire}

Tuist は、[Entire](https://entire.com) リポジトリ内のオープンおよびドラフト状態の [Trails](https://docs.entire.com/guides/trails/overview) に対して、ビルド、テスト、プレビュー、バンドルのインサイトを投稿できます。各 Trail には、実行レポート、失敗したテストと不安定なテストに対する全体変更の所見、そして新しいインサイトが届くたびに Tuist が更新する要約コメントを含む Tuist ゲートが設定されます。Tuist は毎回新しいコメントを投稿するのではなく、既存のコメントを更新します。

プラグインをインストールしても、ビルドやテストは実行されません。既存のワークフローは引き続き結果を Tuist にアップロードし、この統合によってそれらの結果が Trails に取り込まれます。

## セットアップ {#setup}

Tuist アカウントの管理者がプラグインをインストールし、その後 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> や <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> の統合と同様に、リポジトリを Tuist プロジェクトに接続します。

1. アカウントの **Settings → Integrations** を開きます。
2. Entire カードで **Install Entire plugin** を選択します。Tuist と共有したい Entire プロジェクトとリポジトリを選択してください。

   ![アカウント統合から Entire プラグインをインストール](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist に戻り、**Add new project connection** を選択します。**Choose repository to connect to** で、Tuist プロジェクトと Entire リポジトリを選択し、**Create Connection** を選択します。利用可能な Tuist プロジェクトが 1 つだけの場合は、自動的に選択されます。

   ![Tuist プロジェクトを Entire リポジトリに接続](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 既存の認証済み Tuist コマンド（例：<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> を使用）を使用して、CI から結果のアップロードを継続してください。Tuist は結果を各 Trail の現在のヘッドコミットと照合するため、Entire 固有のフラグは不要です。

Tuist プロジェクトは GitHub 接続を維持しながら Entire にも公開できるため、Entire リポジトリが GitHub リポジトリのミラーである場合に便利です。この統合には Tuist の CI エグゼキューターは不要で、CI プロバイダーを変更する必要もありません。

## レポートと権限 {#reports-and-permissions}

プラグインをインストールする際、Trails の検索とレポートの公開に必要な権限を付与します：

| 権限 | 用途 |
| --- | --- |
| リポジトリコンテンツ: 読み取り | Trail イベントを受信し、ヘッドコミットを持つオープンおよびドラフト状態の Trail を検出します。 |
| Checks: 書き込み | Trail のヘッドコミットに Tuist ゲートを公開します。 |
| Findings: 書き込み | 失敗したテストと不安定なテストを検出事項として公開し、新しいレポートで置き換えられた検出事項を解決済みとマークします。 |
| Discussions: 書き込み | 要約コメントを投稿および更新します。この権限がない場合でも、Tuist はゲートと検出事項を公開します。 |

Tuist はソースコードへの書き込みアクセスや、Trails をマージする権限を必要としません。

Tuist は各 Trail に以下の 3 つの項目を公開します：

- **ゲート：** Tuist チェックは、実行レポートと Tuist 上のプロジェクトへのリンクとともに **Gates** の下に表示されます。これは Tuist プラグインの下に一覧表示され、GitHub ミラーの **Checks** ゲートとは別扱いになります。アップロードされた結果からは、期待されるすべての CI ジョブが完了したかどうかを Tuist が判断できないため、`neutral` という結論で完了します。Entire はこれを合格として表示します。検出事項がある場合でもマージはブロックされないため、合格/不合格の強制適用には CI プロバイダーの必須チェックを引き続き使用してください。
- **検出事項：** 失敗したテストと不安定なテストは、Tuist 上のテストケースにリンクする全体変更の検出事項として表示されます。検出事項は Entire の Agent レビューゲートには影響しません。
- **要約コメント：** GitHub や Origin のプルリクエストコメントと同様に、各プロジェクトでは Trail ごとに 1 つの Tuist 実行レポートコメントが保持されます。削除した場合、次のレポートで再度投稿されます。

新しい結果が届くと、Tuist は Trail の現在のヘッドコミットに対して更新されたレポートを公開し、置き換えられる検出事項を解決済みとマークします。再試行によって重複するレビュー、検出事項、またはコメントが作成されることはありません。これは Entire からの公開応答が失われた場合も含みます。Trail を開いたり再開したりすると、そのヘッドコミット用にすでにアップロードされている結果が反映されます。現在のヘッドコミットに対する結果が存在しない場合、Tuist は何も新規に公開しないため、古いコミットのゲートは新しいヘッドの要件を満たすことができません。クローズおよびマージ済みの Trail は更新されません。

Entire カードには、プロジェクトとリポジトリの接続が一覧表示されます。プラグインをアンインストールせずにレポート送信を停止するには、プロジェクト接続で **Manage → Remove connection** を選択してください。すでに公開されたレポートは Entire に残ったままになり、再接続すると新しいレポートが開始されます。プラグインのリポジトリアクセス権限を変更したりアンインストールしたりするには、Entire 内のプロジェクトの **Plugins** 設定を使用してください。

## セルフホストサーバー {#server-configuration}

独自の Tuist サーバーをホストしている場合は、まずデプロイメント用に Entire プラグインを登録して構成してください。<.localized_link href="/guides/server/self-host/server#platform-entire">Entire セルフホスティングの手順</.localized_link> に従い、その後上記のセットアップ手順に戻ってアカウントとプロジェクトを接続してください。
