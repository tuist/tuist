## tuist share でトラックを指定する {#share-tracks}

`tuist share` で公開するワークフローでは、`--track` を使ってトラックを選択します。

```bash
tuist share App --track beta
tuist share App --track nightly
```

## リリースノート {#release-notes}

環境グループにはトラックを、個別のビルドの目的にはリリースノートを使用します。

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

`App` をアプリ名、アプリケーションファイルのパス、または実行可能配布物とその `--executable` オプションに置き換えます。リリースノートは任意のプレーンテキストで、最大 10,000 文字です。最初の空白でない行がプレビューリストの一行スニペットとして表示されるため、ビルド番号やその他の識別情報が一目で確認できます。長い行は切り詰められ、詳細ページに全文が表示されます。検索は表示名と完全なリリースノートに一致し、スニペットに表示されていない行も対象になります。複数行のノートもサポートされており、例えば `--release-notes "$(< release-notes.txt)"` のように指定できます。これらはアプリの表示名やトラックを変更しません。

### 互換性 {#preview-metadata-compatibility}

リリースノートは、ビルドが属するプレビューを変更しません。プレビューが最初に受け取ったノートが保持されます。後からのアップロードでノートがないプレビューにノートを追加することはできますが、既存のノートを上書きしたり削除したりすることはできません。リリースノートが存在する前にアップロードされたプレビューは、ノートなしでも有効です。

セルフホスト型のデプロイメントでは、リリースノートとトラックフィルタリングをサポートするサーバーバージョンと、更新されたクライアントが必要です。古いサーバーはノートを無視します。リストエンドポイントのトラックおよび検索フィルターについては、[API リファレンス](https://tuist.dev/api/docs)をご覧ください。

## プルリクエスト／マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git フォージの連携が必要**
>
> プルリクエスト／マージリクエストに自動的にコメントを投稿するには、<.localized_link href="/guides/server/accounts-and-projects">リモートプロジェクト</.localized_link>を<.localized_link href="/guides/integrations/gitforge/github">Git フォージ</.localized_link>と連携してください。

Tuist プロジェクトが Git プラットフォームと接続されたら、CI でのアプリケーションビルド成功後に <.localized_link href="/cli/share">`tuist share`</.localized_link> を追加します。Tuist はプルリクエスト／マージリクエストに直接プレビューリンクを投稿するため、レビュアーはローカルでビルドせずにテストできます。

![Tuist Preview のリンクを含む GitHub アプリのコメント](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

`tuist share` から JSON 出力を取得するには `--json` を使用します。

```bash
tuist share --json
```

結果をカスタム自動化（例：CI から Slack メッセージを投稿）に利用できます。`url` キーには完全なプレビューリンクが含まれ、`qrCodeURL` はデバイスでプレビューを開くための QR コード画像を指します。

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
