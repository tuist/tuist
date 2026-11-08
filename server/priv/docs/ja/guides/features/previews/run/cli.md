---
{
  "title": "CLIでプレビューを実行",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist CLIを使って、モバイルアプリ、macOSアプリケーション、およびコマンドラインのプレビューを実行します。"
}
---
# CLI でプレビューを実行

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> をインストールし、共有されたプレビューリンクを実行します。プレビューを生成したビルドシステムは不要です。

```bash
tuist run {url}
```

Tuist は、お使いのオペレーティングシステム、CPU アーキテクチャ、およびデスティネーションに互換性のあるビルドを選択します。プライベートなプレビューには、認証とプロジェクトへのアクセス権が必要です。

## モバイルアプリケーション {#mobile-applications}

接続されたデバイスまたはシミュレーターを選択します。

```bash
tuist run --device "My device" {url}
```

Android デバイスとエミュレーターは ADB 経由で接続されている必要があります。また、プレビューページから APK をダウンロードし、そのソースからのインストールを許可する Android デバイスにインストールすることもできます。Apple のビルドは、デスティネーションプラットフォームと一致し、署名要件を満たしている必要があります。IPA の場合、デスティネーションデバイスでプレビューリンクを開いてインストールします。

## コマンドラインプレビュー {#command-line-previews}

`--` の後に引数を渡します。

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--` の後はすべて文字通り転送され、`--verbose`、`--quiet`、および `--path` も含まれます。子引数は Tuist コマンドアナリティクスから除外されます。

プレビューは、現在の作業ディレクトリ、環境、およびターミナルの入出力を使用して実行され、実行可能ファイルの終了ステータスを返します。インストール済みの CLI を置き換えたり、`PATH` に追加したりすることはありません。CLI ディストリビューションは、生成されたプロジェクトが引き続き参照できるように、実行後も Tuist のローカル `previews` キャッシュに残ります。このキャッシュを削除すると、それらの参照先のターゲットも削除されます。

デスクトップおよび CLI プレビューはサンドボックスではなく、現在のユーザーとして実行されます。信頼できる作者やプルリクエストからのビルドのみを実行してください。

## バージョンを選択 {#select-a-version}

`tuist run` は、`latest` を付けたアプリ名、ブランチ名、またはコミットハッシュも受け付けます。

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

これらのセレクターを使用するには、対応する Git メタデータが公開されている必要があります。Git メタデータを省略するワークフローでは、代わりに特定のプレビュー URL を使用してください。

アクセスと組織化については、<.localized_link href="/guides/features/previews#visibility">可視性とトラック</.localized_link>を参照してください。
