---
{
  "title": "リリースカレンダー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistサーバーとKuraの最新バージョン、最近のリリース履歴、および今後の安定版リリースの予定。"
}
---

# リリースカレンダー {#release-calendar}

最新のサーバーおよびKuraのバージョン、最近のリリース、今後のリリース予定を確認できます。チャンネル保証、イメージの固定、バックポートポリシーについては、<.localized_link href="/guides/server/self-host/release/channels">リリースチャンネル</.localized_link>をご覧ください。

安定版の昇格は、<.localized_link href="/cli/release/calendar">CLIのリリーストレイン</.localized_link>に合わせて、毎週月曜日の06:00 UTCにスケジュールされています。次のリリース候補は、スケジュールされた昇格が成功した後にのみ作成されます。障害が発生した場合、各コンポーネントは個別に遅延する可能性があり、メンテナーはスケジュール外で公開を行うことができます。将来のリリース枠は計画であり、公開時刻を保証するものではありません。

パッチリリースとバックポートは、週次スケジュールではなく、必要に応じて提供されます。以下の履歴では、公開されたリリースをそのリリースノートおよび実際の公開日時にリンクしています。

<.release_status status={@release_status} components="server,kura" />
