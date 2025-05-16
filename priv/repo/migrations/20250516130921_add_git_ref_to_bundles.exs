defmodule Tuist.Repo.Migrations.AddGitRefToBundles do
  use Ecto.Migration

  def change do
    alter table("bundles") do
      add :git_ref, :string
    end
  end
end
