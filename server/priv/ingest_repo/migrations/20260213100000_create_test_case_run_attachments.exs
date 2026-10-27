defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunAttachments do
  use Ecto.Migration

  def change do
    create table(:test_case_run_attachments,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, id)"
           ) do
      add :id, :uuid, null: false
      add :test_case_run_id, :uuid, null: false
      add :file_name, :string, null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end
end
