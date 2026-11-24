defmodule Tuist.Repo.Migrations.CreatePulseSymptoms do
  @moduledoc """
  Pulse symptoms come from the symptoms evaluator (`symptoms/` at the repository
  root), which is their only writer. The server mirrors its symptom log
  (`Tuist.Pulse.Workers.SyncSymptomsWorker`) and owns the human state the
  evaluator reads back through `GET /api/internal/symptoms/state`:

  - `pulse_symptoms`: the latest applied revision of each symptom, with typed
    columns for what the page filters and sorts on and `jsonb` for the nested
    parts.
  - `pulse_symptom_revisions`: every applied revision, for history and the
    lifecycle widgets.
  - `pulse_symptom_cursors`: the last log `seq` the mirror processed.
  - `pulse_symptom_acks`, `pulse_symptom_mutes`, `pulse_symptom_outcomes`:
    human state. `change_seq` orders their changes for the evaluator's cursor.
  """
  use Ecto.Migration

  def change do
    create table(:pulse_symptoms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :symptom_key, :string, size: 128, null: false
      add :schema_version, :string, null: false
      add :revision, :integer, null: false
      add :seq, :bigint, null: false
      add :state, :string, null: false
      add :tier, :string, null: false
      add :transition, :string, null: false
      add :merged_into, :uuid
      add :environment, :string, null: false
      add :service, :string, size: 1024, null: false
      add :entity_kind, :string, null: false
      add :entity_key, :text, null: false
      add :title, :text
      add :phenomenon_names, {:array, :string}, null: false, default: []
      add :phenomena, :jsonb, null: false, default: "[]"
      add :score, :float
      add :p_degraded, :float
      add :impact_unit, :string
      add :impact_rate, :float
      add :budget_price, :float
      add :decision, :jsonb
      add :root, :jsonb
      add :suspected_change, :jsonb
      add :evidence, :jsonb
      add :brief_ref, :text
      add :outcome, :jsonb
      add :opened_at, :timestamptz, null: false
      add :revised_at, :timestamptz, null: false
      add :resolved_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The tables are new and empty.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptoms, [:account_id, :state, :revised_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptoms, [:phenomenon_names], using: :gin)

    create table(:pulse_symptom_revisions, primary_key: false) do
      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :revision, :integer, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :seq, :bigint, null: false
      add :state, :string, null: false
      add :tier, :string, null: false
      add :transition, :string, null: false
      add :revised_at, :timestamptz, null: false
      add :document, :jsonb, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_revisions, [:seq])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_revisions, [:account_id, :revised_at])

    create table(:pulse_symptom_cursors, primary_key: false) do
      add :source, :string, primary_key: true
      add :seq, :bigint, null: false, default: 0

      timestamps(type: :timestamptz)
    end

    # Orders changes to acks, mutes and outcomes for the evaluator's cursor.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "CREATE SEQUENCE pulse_symptom_state_changes",
            "DROP SEQUENCE pulse_symptom_state_changes"

    create table(:pulse_symptom_acks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :delete_all),
        null: false

      add :revision, :integer, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :change_seq, :bigint, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_acks, [:symptom_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_acks, [:change_seq])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_acks, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_acks, [:user_id])

    create table(:pulse_symptom_mutes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      # SHA-256 of environment, service, entity kind, entity key and phenomenon.
      add :scope_key, :string, size: 64, null: false
      add :environment, :string, null: false
      add :service, :string, size: 1024, null: false
      add :entity_kind, :string, null: false
      add :entity_key, :text, null: false
      add :phenomenon, :string, null: false
      add :expires_at, :timestamptz, null: false
      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :change_seq, :bigint, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_mutes, [:account_id, :scope_key])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_mutes, [:change_seq])
    # account_id leads the scope_key index above.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_mutes, [:symptom_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_mutes, [:user_id])

    create table(:pulse_symptom_outcomes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :delete_all),
        null: false

      add :outcome, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :change_seq, :bigint, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_outcomes, [:symptom_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:pulse_symptom_outcomes, [:change_seq])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_outcomes, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_outcomes, [:user_id])
  end
end
