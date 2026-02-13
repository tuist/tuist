defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunAttachments do
  use Ecto.Migration

  def up do
    create table(:test_case_run_attachments,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, id)"
           ) do
      add :id, :uuid, null: false
      add :test_case_run_id, :string, null: false
      add :file_name, :string, null: false
      add :content_type, :string, default: ""
      add :size, :"UInt64", default: 0
      add :s3_object_key, :string, null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:test_case_run_attachments)
  end
end
