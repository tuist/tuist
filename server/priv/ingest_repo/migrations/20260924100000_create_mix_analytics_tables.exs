defmodule Tuist.IngestRepo.Migrations.CreateMixAnalyticsTables do
  use Ecto.Migration

  def change do
    create table(:mix_builds,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, inserted_at, id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :account_id, :Int64, null: false
      add :duration_ms, :UInt64, null: false, default: 0
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :is_ci, :Bool, null: false, default: false
      add :elixir_version, :string, null: false, default: ""
      add :otp_version, :string, null: false, default: ""
      add :mix_env, :"LowCardinality(String)", null: false, default: ""
      add :git_branch, :string, null: false, default: ""
      add :git_commit_sha, :string, null: false, default: ""
      add :git_ref, :string, null: false, default: ""
      add :git_remote_url_origin, :string, null: false, default: ""
      add :ci_provider, :"LowCardinality(String)", null: false, default: ""
      add :ci_run_id, :string, null: false, default: ""
      add :ci_project_handle, :string, null: false, default: ""
      add :custom_tags, {:array, :string}, null: false, default: fragment("[]")
      add :custom_values, :"Map(String, String)", null: false, default: fragment("map()")
      add :contract_version, :"LowCardinality(String)", null: false, default: ""
      add :started_at, :"Nullable(DateTime64(6))"
      add :diagnostics_error_count, :UInt32, null: false, default: 0
      add :diagnostics_warning_count, :UInt32, null: false, default: 0
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create table(:mix_diagnostics,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, build_id, inserted_at, id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :build_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :severity, :"Enum8('warning' = 0, 'error' = 1)", null: false
      add :file, :string, null: false, default: ""
      add :module, :string, null: false, default: ""
      add :message, :string, null: false, default: ""
      add :line, :"Nullable(UInt32)"
      add :column, :"Nullable(UInt32)"
      add :compiler, :"LowCardinality(String)", null: false, default: ""
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
