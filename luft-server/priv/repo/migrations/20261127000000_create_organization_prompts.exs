defmodule LuftServer.Repo.Migrations.CreateOrganizationPrompts do
  use Ecto.Migration

  def change do
    create table(:organization_prompts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :organization_id, :bigint, null: false
      add :name, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_prompts, [:organization_id, :name])

    alter table(:thread_messages) do
      add :prompt, :map
    end
  end
end
