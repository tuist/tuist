defmodule Tuist.Repo.Migrations.AddGitMetadataToQARuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :vcs_repository_full_handle, :string, null: true
      add :vcs_provider, :integer, null: true
      add :git_ref, :string, null: true
    end

    create index(:qa_runs, [:vcs_repository_full_handle, :vcs_provider, :git_ref])
  end
end
