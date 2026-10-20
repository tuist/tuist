defmodule Atlas.Repo.Migrations.RemoveAvatarUrlFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :avatar_url, :string
    end
  end
end
