defmodule Tuist.IngestRepo.Migrations.CreateCargoAnalytics do
  use Ecto.Migration
  alias Tuist.IngestRepo.Migration

  def change do
    create table(:cargo_builds,
             primary_key: false,
             engine: Migration.engine("MergeTree"),
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, inserted_at, id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :account_id, :Int64, null: false
      add :duration_ms, :UInt32, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :is_ci, :Bool, null: false, default: false

      for field <-
            ~w(command rust_version contract_version git_branch git_commit_sha git_ref git_remote_url_origin ci_provider ci_run_id ci_project_handle ci_host)a do
        add field, :string, null: false, default: ""
      end

      add :started_at, :"Nullable(DateTime64(6))"
      add :inserted_at, :naive_datetime, null: false
    end

    create table(:cargo_compilations,
             primary_key: false,
             engine: Migration.engine("MergeTree"),
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, build_id, start_offset_ms, id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :name, :string, null: false
      add :source, :string, null: false
      add :kind, :string, null: false
      add :dependencies, {:array, :string}, null: false, default: fragment("[]")
      add :start_offset_ms, :UInt32, null: false
      add :duration_ms, :UInt32, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :diagnostics, :string, null: false, default: "[]"
      add :inserted_at, :naive_datetime, null: false
    end
  end
end
