---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI、そのコマンド、およびワークフローに合わせた設定方法。"
}
---
# CLI {#cli}

Tuist CLI は Tuist と対話するためのインターフェースの一つであり、<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>を使用している場合にもっとも一般的です。プロジェクトの生成、バイナリのキャッシュ、テストの実行、プレビューの共有などを行うコマンドを提供します。

## はじめに {#getting-started}

まだ Tuist をインストールしていない場合は、<.localized_link href="/guides/install-tuist">インストールガイド</.localized_link>に従って開始してください。

インストール後、ターミナルで `tuist` を実行すると、利用可能なコマンドの一覧が表示されます：

```bash
tuist --help
```

## 設定 {#configuration}

CLI の動作は `tuist.toml` ファイルで構成できます。利用可能なすべてのオプションについては、<.localized_link href="/references/tuist-toml">tuist.toml リファレンス</.localized_link>を参照してください。

## トラブルシューティング {#troubleshooting}

問題が発生した場合は、セッションログやネットワーク記録を含む問題診断ツールについて<.localized_link href="/cli/debugging">デバッグガイド</.localized_link>を確認してください。
