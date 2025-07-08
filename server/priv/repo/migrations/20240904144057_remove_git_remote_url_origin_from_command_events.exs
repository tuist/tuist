defmodule Tuist.Repo.Migrations.RemoveGitRemoteUrlOriginFromCommandEvents do
  use Ecto.Migration

  def up do
    alter table(:command_events) do
      remove :git_remote_url_origin
    end
  end

  def down do
    alter table(:command_events) do
      add :git_remote_url_origin, :string, null: true
    end
  end
end
