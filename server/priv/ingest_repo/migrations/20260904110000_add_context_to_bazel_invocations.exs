defmodule Tuist.IngestRepo.Migrations.AddContextToBazelInvocations do
  use Ecto.Migration

  def change do
    alter table(:bazel_invocations) do
      add :target_patterns, :"Array(String)", default: fragment("[]")
      add :git_branch, :string, default: ""
      add :git_commit_sha, :string, default: ""
      add :is_ci, :boolean, default: false
    end
  end
end
