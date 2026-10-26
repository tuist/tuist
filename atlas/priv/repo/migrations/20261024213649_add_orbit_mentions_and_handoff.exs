defmodule Atlas.Repo.Migrations.AddOrbitMentionsAndHandoff do
  use Ecto.Migration

  def change do
    alter table(:orbit_messages) do
      add :mentioned_user_ids, {:array, :uuid}, null: false, default: []
      add :notice_kind, :text
    end

    create constraint(:orbit_messages, :orbit_messages_notice_kind,
             check: "notice_kind IS NULL OR (kind = 'system' AND notice_kind = 'handoff')"
           )

    create constraint(:orbit_messages, :orbit_messages_mentions,
             check:
               "cardinality(mentioned_user_ids) <= 10 AND (kind = 'human' OR cardinality(mentioned_user_ids) = 0)"
           )
  end
end
