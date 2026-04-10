defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunArguments do
  use Ecto.Migration

  def up do
    create table(:test_case_run_arguments,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, id)"
           ) do
      add :id, :uuid, null: false
      add :test_case_run_id, :uuid, null: false
      add :name, :string, null: false
      add :status, :"LowCardinality(String)", null: false
      add :duration, :Int32, null: false, default: 0
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:test_case_run_arguments)
  end
end
