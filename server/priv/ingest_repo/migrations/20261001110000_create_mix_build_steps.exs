defmodule Tuist.IngestRepo.Migrations.CreateMixBuildSteps do
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  def change do
    create table(:mix_build_steps,
             primary_key: false,
             engine: Migration.engine("MergeTree"),
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, build_id, start_offset_ms, id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      # The kind of work: type_check, write, compiler or other. Compiling a
      # file is not stored here; it is derived from mix_compiled_files.
      add :category, :"LowCardinality(String)", null: false
      add :title, :string, null: false
      # The project file the step is about, empty when it concerns the whole build.
      add :path, :string, null: false, default: ""
      add :start_offset_ms, :UInt32, null: false
      add :duration_ms, :UInt32, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
