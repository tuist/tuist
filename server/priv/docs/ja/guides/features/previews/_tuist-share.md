## tuist share でのトラック {#share-tracks}

`tuist share` で公開するワークフローでは、`--track` を使用してトラックを選択します:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## リリースノート {#release-notes}

環境グループにはトラックを、個別のビルドの目的にはリリースノートを使用します:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

`App` をアプリ名、アプリケーションファイルパス、または実行可能配布物とその `--executable` オプションに置き換えます。リリースノートは任意のプレーンテキストで、最大10,000文字です。最初の空白でない行がプレビューリストの1行スニペットとして表示されるため、ビルド番号やその他の識別情報が一目で確認できます。長い行は切り詰められ、詳細ページに全文が表示されます。検索は表示名と完全なリリースノート（スニペットに表示されていない行を含む）に一致します。複数行のノートもサポートされており、例えば `--release-notes "$(< release-notes.txt)"` のように指定できます。これらはアプリの表示名やトラックを変更しません。

### 互換性 {#preview-metadata-compatibility}

リリースノートは、ビルドが属するプレビューを変更しません。プレビューが最初に受け取ったノートが保持されます。後からのアップロードでノートがないプレビューにノートを追加することはできますが、既存のノートを上書きしたり消去したりすることはできません。リリースノートが存在する前にアップロードされたプレビューは、ノートなしでも有効です。

セルフホスト型のデプロイメントでは、リリースノートとトラックフィルタリングをサポートするサーバーバージョンと、更新されたクライアントが必要です。古いサーバーはノートを無視します。リストエンドポイントのトラックおよび検索フィルターについては、[API リファレンス](https://tuist.dev/api/docs)を参照してください。

## プルリクエスト/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git フォージの統合が必要**
>
> プルリクエスト/マージリクエストの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">リモートプロジェクト</.localized_link>を Git フォージと統合してください: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>、または <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。

Tuist プロジェクトが Git プラットフォームに接続されたら、CI でのアプリケーションビルド成功後に <.localized_link href="/cli/share">`tuist share`</.localized_link> を追加します。Tuist はプレビューリンクをプルリクエスト/マージリクエストに直接投稿するため、レビュアーはローカルでビルドせずにテストできます:

![Tuist Preview リンク付きの GitHub アプリコメント](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

`tuist share` から JSON 出力を取得するには `--json` を使用します:

```bash
tuist share --json
```

結果をカスタム自動化（例: CI から Slack メッセージを投稿）に利用できます。`url` キーには完全なプレビューリンクが含まれ、`qrCodeURL` はデバイスでプレビューを開くための QR コード画像を指します:

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
