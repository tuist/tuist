---
{
  "title": "CLI でプレビューを実行する",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist CLI を使用して、モバイルアプリ、macOS アプリケーション、およびコマンドラインのプレビューを実行します。"
}
---
# CLIでプレビューを実行

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>をインストールし、共有されたプレビューリンクを実行します。プレビューを生成したビルドシステムは不要です:

```bash
tuist run {url}
```

Tuistは、お使いのOS、CPUアーキテクチャ、およびデスティネーションに互換性のあるビルドを選択します。プライベートなプレビューには認証とプロジェクトへのアクセス権が必要です。

## モバイルアプリケーション {#mobile-applications}

接続されているデバイスまたはシミュレータを選択してください:

```bash
tuist run --device "My device" {url}
```

AndroidデバイスおよびエミュレータはADB経由で接続されている必要があります。また、プレビューページからAPKをダウンロードし、そのソースからのインストールを許可しているAndroidデバイスにインストールすることもできます。Appleビルドはデスティネーションプラットフォームと一致し、署名要件を満たしている必要があります。IPAの場合、デスティネーションデバイスでプレビューリンクを開いてインストールしてください。

## コマンドラインプレビュー {#command-line-previews}

`--`の後に引数を渡します:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--`以降のすべては、`--verbose`、`--quiet`、および`--path`を含め、そのまま転送されます。子引数はTuistのコマンド分析からは除外されます。

プレビューは現在の作業ディレクトリ、環境、およびターミナルの入出力を使用して実行され、実行可能ファイルの終了ステータスを返します。これはインストール済みのCLIを置き換えたり、`PATH`に追加したりするものではありません。CLI配布物は実行後もTuistのローカル`previews`キャッシュに残り、生成されたプロジェクトがそれらを参照し続けられるようになります。このキャッシュを削除すると、それらの参照先のターゲットも削除されます。

デスクトップおよびCLIプレビューはサンドボックス内ではなく、現在のユーザーとして実行されます。信頼できる作者やプルリクエストからのビルドのみを実行してください。

## バージョンを選択 {#select-a-version}

`tuist run`は、`latest`付きのアプリ名、ブランチ名、またはコミットハッシュも受け付けます:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

これらのセレクタを使用するには、対応するGitメタデータが公開されている必要があります。Gitメタデータを省略するワークフローの場合は、代わりに特定のプレビューURLを使用してください。

アクセス権限と整理については、<.localized_link href="/guides/features/previews#visibility">可視性とトラック</.localized_link>を参照してください。
