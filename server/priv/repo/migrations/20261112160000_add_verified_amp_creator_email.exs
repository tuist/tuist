defmodule Tuist.Repo.Migrations.AddVerifiedAmpCreatorEmail do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      add :amp_creator_email, :string
    end
  end
end
