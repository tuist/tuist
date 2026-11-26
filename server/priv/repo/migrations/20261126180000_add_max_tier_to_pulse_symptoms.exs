defmodule Tuist.Repo.Migrations.AddMaxTierToPulseSymptoms do
  @moduledoc """
  The evaluator re-decides a symptom's tier every window, so a symptom that
  paged or reached the board can drop to audit while it quiets down and then
  resolve there. `max_tier` keeps the highest tier any applied revision had,
  which the Symptoms page filters on. Existing rows take it from their
  revisions.
  """
  use Ecto.Migration

  def up do
    alter table(:pulse_symptoms) do
      # A constant default is a metadata-only change on PostgreSQL 11+.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :max_tier, :string, null: false, default: "audit"
    end

    flush()

    # One row per symptom of the ops-only Pulse mirror: a small table.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE pulse_symptoms AS s
    SET max_tier = m.max_tier
    FROM (
      SELECT
        symptom_id,
        CASE
          WHEN bool_or(tier = 'page') THEN 'page'
          WHEN bool_or(tier = 'board') THEN 'board'
          ELSE 'audit'
        END AS max_tier
      FROM pulse_symptom_revisions
      GROUP BY symptom_id
    ) AS m
    WHERE m.symptom_id = s.id AND s.max_tier <> m.max_tier
    """)
  end

  def down do
    alter table(:pulse_symptoms) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :max_tier
    end
  end
end
