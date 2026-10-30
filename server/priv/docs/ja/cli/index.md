---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI、そのコマンド、およびワークフローに合わせた設定方法。"
}
---
# CLI {#cli}

Tuist CLI は Tuist と対話するためのインターフェースの 1 つで、<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>を使用している場合に最も一般的に利用されます。プロジェクトの生成、バイナリのキャッシュ、テストの実行、プレビューの共有などを行うコマンドを提供します。

## はじめに {#getting-started}

まだ Tuist をインストールしていない場合は、<.localized_link href="/guides/install-tuist">インストールガイド</.localized_link>に従ってセットアップしてください。

インストールが完了したら、ターミナルで `tuist` を実行して利用可能なコマンドの一覧を確認できます:

```bash
tuist --help
```

## 設定 {#configuration}

CLI の動作は `tuist.toml` ファイルで構成できます。利用可能なすべてのオプションについては、<.localized_link href="/references/tuist-toml">tuist.toml リファレンス</.localized_link>を参照してください。

## トラブルシューティング {#troubleshooting}

問題が発生した場合は、セッションログやネットワーク記録を含む問題診断ツールについて、<.localized_link href="/cli/debugging">デバッグガイド</.localized_link>を確認してください。
