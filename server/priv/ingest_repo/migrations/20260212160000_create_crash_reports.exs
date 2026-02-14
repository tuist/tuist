defmodule Tuist.IngestRepo.Migrations.CreateCrashReports do
  use Ecto.Migration

  def up do
    create table(:test_case_run_crash_reports,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, id)"
           ) do
      add :id, :uuid, null: false
      add :exception_type, :string, default: ""
      add :signal, :string, default: ""
      add :exception_subtype, :string, default: ""
      add :triggered_thread_frames, :string, default: ""
      add :test_case_run_id, :uuid, null: false
      add :test_case_run_attachment_id, :uuid
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:test_case_run_crash_reports)
  end
end
