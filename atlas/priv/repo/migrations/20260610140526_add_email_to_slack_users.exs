defmodule Atlas.Repo.Migrations.AddEmailToSlackUsers do
  use Ecto.Migration

  def change do
    alter table(:slack_users) do
      add :email, :string
    end
  end
end
