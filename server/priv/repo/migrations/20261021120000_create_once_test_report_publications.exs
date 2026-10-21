defmodule Tuist.Repo.Migrations.CreateOnceTestReportPublications do
  use Ecto.Migration

  def change do
    create table(:once_test_report_publications, primary_key: false) do
      add :id, references(:once_runs, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :payload, :binary
      add :state, :string, null: false, default: "preparing"
      add :preparation_attempts, :integer, null: false, default: 0
      add :preparation_error, :string
      add :owner, :string
      add :first_attempt_at, :timestamptz
      add :next_chunk, :integer, null: false, default: 0
      add :in_flight_chunk, :integer
      add :effects_dispatched_at, :timestamptz
      timestamps(type: :timestamptz)
    end
  end
end
