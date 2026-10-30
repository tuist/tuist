---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI プロバイダー · Runner · 機能 · ガイド · Tuist",
  "description": "パイプラインタグによるマシン選択で、Tuist Runner 上で GitLab CI ジョブを実行します。"
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、招待制です。アカウントへのアクセスをリクエストするには[お問い合わせください](mailto:contact@tuist.dev)。

パイプラインは GitLab 内に留まります。Tuist は各ジョブに対して隔離された Linux または macOS マシンを提供し、そのログと結果を GitLab および Tuist ダッシュボードに報告します。GitLab 19.3 以降が必要です。GitLab.com およびパブリック HTTPS で到達可能なセルフマネージドインスタンスがサポートされています。

1. **GitLab ランナーを作成します。** プロジェクトの**Settings → CI/CD → Runners**で、プロジェクトランナーを作成します。グループランナーを使用することもできます。ランナータグとして使用したい Tuist プロファイルラベル（例：`tuist-linux`および`tuist-macos`）をすべて追加し、**Run untagged jobs**を無効にします。GitLab が表示する認証トークン（`glrt-`で始まる）を保管してください。独自のマシンにランナーをインストールする必要はありません。
2. **Tuist で一度接続します。** **Settings → Integrations**で、GitLab CI カードの**Connect**を選択します。GitLab URL とランナー認証トークンを入力します。この接続は、異なるプロファイルを使用するジョブに対応できます。トークンは暗号化されて保存され、二度と表示されることはありません。オプションで、マージリクエストパイプラインがキャッシュボリュームを保存できるように API アクセストークンを追加します。[マージリクエストパイプライン](#merge-request-pipelines)を参照してください。
3. **各ジョブでマシンを選択します。** ジョブの`tags`に、<.localized_link href="/guides/features/runners/profiles">Tuist プロファイルラベル</.localized_link>を正確に 1 つ設定します。登録済みの GitLab ランナーも同じタグを持っている限り、他のタグも許可されます。

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

4. **プッシュして監視します。** Tuist は 1 分以内にポーリングを開始します。ジョブは**Runners**の下に表示され、GitLab ジョブへのリンク、ログ、およびマシンのメトリクスが確認できます。GitLab はジョブの実行中にログを受信し、Tuist は完了時にマスクされたログを受信します。

Tuist は各割り当てから`CI_JOB_TAGS`を読み取り、接続された Tuist アカウント内でプロファイルを解決します。`CI_RUNNER_TAGS`からマシンを推測したり、デフォルトのプロファイルを使用したりすることはありません。Tuist プロファイルタグが見つからない、不明、または複数ある場合、取得したジョブは失敗し、その GitLab ログに説明が記録されます。パイプライン変数で`CI_JOB_TAGS`を上書きしないでください。

## 実行環境 {#execution-environment}

ジョブは隔離されたマシン内で GitLab の**shell executor**を使用します。チェックアウト、CI 変数、`before_script`、`script`、`after_script`、アーティファクト、およびキャンセルは GitLab Runner によって処理されます。パイプラインの`image:`および`services:`設定はこのシェル環境を構成しません。<.localized_link href="/guides/features/runners/profiles">ランナーイメージ</.localized_link>にインストールされているツールを使用するか、スクリプト内でインストールしてください。

再利用可能なランナー認証トークンは Tuist サーバー上に残ります。マシンは割り当てられたジョブの資格情報のみを受け取ります。キャッシュ署名の権限は現在、GitLab ジョブでは付与されていません。カスタム Linux キャッシュボリュームは GitLab の API を介してジョブの ID と保存権限を検証します。上書き可能な CI 変数は信頼を確立しません。

Tuist がジョブを取得するとすぐに、GitLab はジョブを実行中としてマークし、タイムアウトを開始します。Tuist がすでに取得したジョブがアカウントの同時実行数制限を使い切っている間、追加のジョブは GitLab で待機状態のままになります。取得されたジョブは、最大 12 時間まで、ジョブのタイムアウトまでマシンを待ちます。その時間までに利用可能なマシンがない場合、Tuist は割り当てを`runner_system_failure`で失敗させ、上記のリトライポリシーにより GitLab が再試行します。同じポリシーはランナーマシンの喪失にも適用されます。

## トークンの更新と切断 {#rotating-tokens-and-disconnecting}

接続のトークンを更新し、**Save changes**を選択して回転させます。トークンを空白のままにすると、既存の資格情報が保持されます。

**Disconnect**は取得を停止し、待機中の割り当てを失敗させます。実行中のジョブは独自の資格情報で続行されます。GitLab に到達できない場合、Tuist は待機中の割り当てのキャンセルを再試行しながら、無効化された接続を保持します。これらの割り当てが確定すると、接続は削除されます。

## キャッシュボリューム {#cache-volumes}

<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>を使用して、ジョブ間で Xcode、モジュール、Gradle のキャッシュおよびその他のディレクトリを保持します。チェックアウト後、それらを使用するコマンドの前に追加してください。

### マージリクエストパイプライン {#merge-request-pipelines}

プロジェクトのプッシュ、スケジュール、ウェブパイプラインは変更をキャッシュボリュームに保存します。マージリクエストパイプラインはキャッシュを使用し、接続に API アクセストークンがある場合にのみ変更を保存します。

1. GitLab で、**Reporter**ロールと`read_api`スコープを持つプロジェクトまたはグループアクセストークンを作成します。グループトークンは、Tuist ランナーで実行されるグループ内のすべてのプロジェクトを対象とします。
2. **Settings → Integrations**で、GitLab CI カードの**API access token**に貼り付け、**Save changes**を選択します。

Tuist はその後、各マージリクエストパイプラインのマージリクエストを読み取ります。プロジェクト自体のブランチから開かれたマージリクエストのパイプラインは、マージリクエストのソースブランチの下に変更を保存するため、ランナープロファイルの<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">ブランチ設定</.localized_link>がそのブランチに適用されます。フォークからのマージリクエストは保存されません。Tuist がマージリクエストを読み取れない場合、ジョブは引き続き実行されキャッシュを使用しますが、その変更は破棄されます。
