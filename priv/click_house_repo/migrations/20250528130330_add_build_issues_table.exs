defmodule Tuist.ClickHouseRepo.Migrations.AddBuildIssuesTable do
  use Ecto.Migration

  def change do
    create table(:build_issues,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (build_run_id, inserted_at)"
           ) do
      add :type, :"Enum8('warning' = 0, 'error' = 1)", null: false
      add :target, :string, null: false
      add :project, :string, null: false
      add :title, :string, null: false
      add :signature, :string
      add :path, :string
      add :message, :string
      add :starting_line, :UInt64, null: false
      add :ending_line, :UInt64, null: false
      add :starting_column, :UInt64, null: false
      add :ending_column, :UInt64, null: false
      add :build_run_id, :uuid, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end

    # We need to add the column using raw SQL as the enum is too large to be an atom (and the column typed needs to be specified as an atom)
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_issues ADD COLUMN step_type Enum8(
      'c_compilation' = 0,
      'swift_compilation' = 1,
      'script_execution' = 2,
      'create_static_library' = 3,
      'linker' = 4,
      'copy_swift_libs' = 5,
      'compile_assets_catalog' = 6,
      'compile_storyboard' = 7,
      'write_auxiliary_file' = 8,
      'link_storyboards' = 9,
      'copy_resource_file' = 10,
      'merge_swift_module' = 11,
      'xib_compilation' = 12,
      'swift_aggregated_compilation' = 13,
      'precompile_bridging_header' = 14,
      'other' = 15,
      'validate_embedded_binary' = 16,
      'validate' = 17
    )
    """
  end
end
