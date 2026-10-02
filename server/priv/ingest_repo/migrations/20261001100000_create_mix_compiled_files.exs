defmodule Tuist.IngestRepo.Migrations.CreateMixCompiledFiles do
  use Ecto.Migration

  def change do
    create table(:mix_compiled_files,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, build_id, path) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :path, :string, null: false
      # Milliseconds from the start of the compile to when the file started
      # compiling. Null when the client could not observe it.
      add :start_offset_ms, :"Nullable(UInt32)"
      add :compile_duration_ms, :UInt32, null: false, default: 0
      add :wait_duration_ms, :UInt32, null: false, default: 0
      add :modules, {:array, :string}, null: false, default: fragment("[]")
      # The project files this file references, aligned by index with how
      # strongly: compile (needed while it compiles), export (its struct or
      # an import) or runtime (only called from inside functions).
      add :dependency_paths, {:array, :string}, null: false, default: fragment("[]")
      add :dependency_kinds, {:array, :string}, null: false, default: fragment("[]")
      # One entry per wait, aligned by index: how long the file sat paused
      # until a module it needed was available, and when the wait began on
      # the same clock as start_offset_ms (null when the client could not
      # place it). Used to leave that time out of the build timeline.
      add :wait_durations_ms, {:array, :UInt32}, null: false, default: fragment("[]")

      add :wait_start_offsets_ms, {:array, :"Nullable(UInt32)"},
        null: false,
        default: fragment("[]")

      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
