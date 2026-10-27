defmodule Atlas.Repo.Migrations.CreateErrorSummaryRuns do
  use Ecto.Migration

  def change do
    create table(:error_summary_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scheduled_for, :timestamptz, null: false
      add :window_start, :timestamptz, null: false
      add :window_end, :timestamptz, null: false
      add :input_fingerprint, :string, size: 64, null: false
      add :issue_ids, {:array, :uuid}, null: false, default: []
      add :issue_count, :integer, null: false, default: 0
      add :status, :string, null: false
      add :summary, :text
      add :attention, {:array, :map}, null: false, default: []
      add :slack_channel_id, :string, null: false
      add :slack_message_ts, :string
      add :generated_at, :timestamptz
      add :delivered_at, :timestamptz
      add :failure_reason, :text

      timestamps(type: :timestamptz)
    end

    create unique_index(:error_summary_runs, [:scheduled_for])
    create index(:error_summary_runs, [:input_fingerprint, :status])
  end
end
