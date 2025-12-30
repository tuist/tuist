defmodule Tuist.Repo.Migrations.AddVCSToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :vcs_repository_full_handle, :string, null: true
      add :vcs_provider, :integer, null: true
    end
  end
end
