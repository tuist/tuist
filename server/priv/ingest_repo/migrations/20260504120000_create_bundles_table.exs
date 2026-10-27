defmodule Tuist.IngestRepo.Migrations.CreateBundlesTable do
  use Ecto.Migration

  def up do
    create table(:bundles,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, inserted_at, id)"
           ) do
      add :id, :uuid, null: false
      add :app_bundle_id, :string, null: false
      add :name, :string, null: false
      add :install_size, :Int64, null: false
      add :download_size, :"Nullable(Int64)"
      add :git_branch, :"Nullable(String)"
      add :git_commit_sha, :"Nullable(String)"
      add :git_ref, :"Nullable(String)"
      add :supported_platforms, :"Array(LowCardinality(String))", default: fragment("[]")
      add :version, :string, null: false
      add :type, :"LowCardinality(String)", null: false
      add :project_id, :Int64, null: false
      add :uploaded_by_account_id, :"Nullable(Int64)"

      add :inserted_at, :"DateTime64(6)", default: fragment("now64(6)"), null: false
      add :updated_at, :"DateTime64(6)", default: fragment("now64(6)"), null: false
    end
  end

  def down do
    drop table(:bundles)
  end
end
