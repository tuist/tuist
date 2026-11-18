defmodule Tuist.Repo.Migrations.AddAmpCreatorAttribution do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      add :amp_creator_user_id, :string
      add :amp_creator_username, :string
      add :amp_creator_name, :string
    end
  end
end
