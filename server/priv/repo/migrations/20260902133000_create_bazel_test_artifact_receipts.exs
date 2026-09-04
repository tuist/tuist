defmodule Tuist.Repo.Migrations.CreateBazelTestArtifactReceipts do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:bazel_test_artifact_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :invocation_id, :string, null: false
      add :target_label, :string, null: false
      add :action_digest, :string, null: false
      add :artifact_kind, :string, null: false
      add :artifact_digest, :string, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(
             :bazel_test_artifact_receipts,
             [
               :project_id,
               :invocation_id,
               :target_label,
               :action_digest,
               :artifact_kind,
               :artifact_digest
             ],
             name: :bazel_test_artifact_receipts_identity_index,
             concurrently: true
           )
  end
end
