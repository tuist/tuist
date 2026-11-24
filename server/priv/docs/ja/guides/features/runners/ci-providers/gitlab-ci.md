---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI プロバイダー · Runner · 機能 · ガイド · Tuist",
  "description": "パイプラインタグによるマシン選択で、Tuist Runner 上で GitLab CI ジョブを実行します。"
}
---
# GitLab CI {#gitlab-ci}

<!-- @snippet: ./_invite-only -->

パイプラインは GitLab 上に残ります。Tuist は各ジョブに対して隔離された Linux または macOS マシンを提供し、そのログと結果を GitLab および Tuist ダッシュボードに報告します。GitLab 19.3 以降が必要です。パブリック HTTPS 経由でアクセス可能な GitLab.com およびセルフマネージドインスタンスがサポートされています。

1. **GitLab ランナーを作成する** プロジェクトの **Settings → CI/CD → Runners** でプロジェクトランナーを作成します。グループランナーを使用することもできます。使用したい Tuist プロファイルラベルをすべてランナータグとして追加し（例: `tuist-linux` と `tuist-macos`）、**Run untagged jobs** を無効にしてください。GitLab が表示する認証トークン（`glrt-` で始まる）を保管してください。独自のマシンにランナーをインストールする必要はありません。
2. **Tuist で一度接続する** **Settings → Integrations** で、GitLab CI カードの **Connect** を選択します。GitLab の URL とランナー認証トークンを入力してください。この接続は、異なるプロファイルを使用するジョブに対応できます。トークンは暗号化されて保存され、二度と表示されることはありません。オプションで API アクセストークンを追加すると、マージリクエストパイプラインがキャッシュボリュームを保存できるようになります。[マージリクエストパイプライン](#merge-request-pipelines)を参照してください。
3. **各ジョブでマシンを選択する** ジョブの `tags` に <.localized_link href="/guides/features/runners/profiles">Tuist プロファイルラベル</.localized_link> を正確に 1 つ設定します。登録済みの GitLab ランナーにも同じタグが付与されている限り、他のタグも許可されます。

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **プッシュして監視する** Tuist は 1 分以内にポーリングを開始します。ジョブは **Runners** に表示され、GitLab ジョブへのリンク、ログ、およびマシンのメトリクスが確認できます。GitLab はジョブの実行中にログを受信し、Tuist は終了時にマスクされたログを受信します。

Tuist は各アサインメントから `CI_JOB_TAGS` を読み取り、接続された Tuist アカウント内でプロファイルを解決します。`CI_RUNNER_TAGS` からマシンを推測したり、デフォルトプロファイルを使用したりすることはありません。Tuist プロファイルタグが見つからない、不明、または複数ある場合、取得したジョブは失敗し、その GitLab ログに説明が記録されます。パイプライン変数で `CI_JOB_TAGS` を上書きしないでください。

## 実行環境 {#execution-environment}

ジョブは隔離されたマシン内で GitLab の **shell executor** を使用します。チェックアウト、CI 変数、`before_script`、`script`、`after_script`、成果物、およびキャンセルは GitLab Runner によって処理されます。パイプラインの `image:` および `services:` 設定はこのシェル環境を構成しません。<.localized_link href="/guides/features/runners/profiles">ランナーイメージ</.localized_link> にインストールされているツールを使用するか、スクリプト内でインストールしてください。

再利用可能なランナー認証トークンは Tuist サーバー上に残ります。マシンは割り当てられたジョブの資格情報のみを受け取ります。現在、GitLab ジョブに対するキャッシュ署名権限は付与されていません。カスタム Linux キャッシュボリュームは GitLab の API を介してジョブの ID と保存権限を検証します。上書き可能な CI 変数は信頼を確立しません。

GitLab は、Tuist がジョブを取得するとすぐに実行中としてマークし、タイムアウトを開始します。Tuist がすでに取得したジョブがアカウントの同時実行数制限を使い切っている間、それ以上のジョブは GitLab で保留状態になります。取得されたジョブは、最大 12 時間まで、ジョブのタイムアウトまでマシンを待ちます。その時間までに利用可能なマシンがない場合、Tuist はアサインメントを `runner_system_failure` で失敗させ、上記のリトライポリシーにより GitLab が再試行します。同じポリシーはランナーマシンの喪失にも適用されます。

## トークンの更新と切断 {#rotating-tokens-and-disconnecting}

接続のトークンを更新し、**Save changes** を選択してローテーションします。トークンを空白のままにすると、既存の資格情報が保持されます。

**Disconnect** は取得を停止し、待機中のアサインメントを失敗させます。実行中のジョブは独自の資格情報で続行されます。GitLab に到達できない場合、Tuist は待機中のアサインメントのキャンセルを再試行しながら、無効化された接続を保持します。これらのアサインメントが確定すると、接続は削除されます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュやその他のディレクトリを保持します。これらはチェックアウト後、それらを使用するコマンドの前に追加してください。

### マージリクエストパイプライン {#merge-request-pipelines}

プロジェクトのプッシュ、スケジュール、ウェブパイプラインは変更をキャッシュボリュームに保存します。マージリクエストパイプラインはキャッシュを使用しますが、接続に API アクセストークンがある場合にのみ変更を保存します。

1. GitLab で、**Reporter** ロールと `read_api` スコープを持つプロジェクトまたはグループアクセストークンを作成します。グループトークンは、Tuist ランナー上で実行されるグループ内のすべてのプロジェクトを対象とします。
2. **Settings → Integrations** で、GitLab CI カードの **API access token** に貼り付け、**Save changes** を選択します。

その後、Tuist は各マージリクエストパイプラインのマージリクエストを読み取ります。プロジェクト自体のブランチから開かれたマージリクエストのパイプラインは、マージリクエストのソースブランチの下に変更を保存するため、ランナープロファイルの <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">ブランチ設定</.localized_link> がそのブランチに適用されます。フォークからのマージリクエストは決して保存されません。Tuist がマージリクエストを読み取れない場合、ジョブは実行されキャッシュを使用しますが、その変更は破棄されます。
