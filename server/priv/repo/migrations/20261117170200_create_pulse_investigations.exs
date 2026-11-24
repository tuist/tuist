# The tables are new and empty, so their indexes cannot block real traffic.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreatePulseInvestigations do
  @moduledoc """
  The briefs Pulse writes from code for a symptom at board or page tier
  (`Tuist.Pulse.Investigations`):

  - `pulse_investigations`: one row per trigger on a symptom; symptoms merged
    into a root join its latest row through `member_symptom_ids`. The name is
    the evaluator's: it reads these rows back as `investigations`.
  - `pulse_briefs`: versioned briefs per symptom, one per trigger.
  - `pulse_brief_steps`: a brief's mitigate-now steps and the status people
    set on them.

  `change_seq` draws from `pulse_symptom_state_changes`, like acks, mutes and
  outcomes, so the evaluator reads investigations back with the same cursor.
  """
  use Ecto.Migration

  def change do
    create table(:pulse_investigations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :delete_all),
        null: false

      add :member_symptom_ids, {:array, :uuid}, null: false, default: []
      add :trigger, :string, null: false
      add :trigger_seq, :bigint, null: false
      add :request_id, :uuid, null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :change_seq, :bigint, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:pulse_investigations, [:request_id])
    create unique_index(:pulse_investigations, [:change_seq])
    create index(:pulse_investigations, [:account_id, :inserted_at])
    create index(:pulse_investigations, [:symptom_id, :inserted_at])
    create index(:pulse_investigations, [:requested_by_id])

    create table(:pulse_briefs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :symptom_id, references(:pulse_symptoms, type: :uuid, on_delete: :delete_all),
        null: false

      add :investigation_id,
          references(:pulse_investigations, type: :uuid, on_delete: :nilify_all)

      add :version, :integer, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:pulse_briefs, [:symptom_id, :version])
    create unique_index(:pulse_briefs, [:investigation_id])
    create index(:pulse_briefs, [:account_id])

    create table(:pulse_brief_steps, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :brief_id, references(:pulse_briefs, type: :uuid, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :kind, :string, null: false
      add :title, :text, null: false
      add :detail, :text
      add :command, :text, null: false
      add :reverse_command, :text, null: false
      add :safety, :string, null: false
      add :safety_reason, :text
      add :status, :string, null: false, default: "proposed"
      add :status_by_id, references(:users, on_delete: :nilify_all)
      add :status_changed_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:pulse_brief_steps, [:brief_id, :position])
    create index(:pulse_brief_steps, [:account_id])
    create index(:pulse_brief_steps, [:status_by_id])
  end
end
