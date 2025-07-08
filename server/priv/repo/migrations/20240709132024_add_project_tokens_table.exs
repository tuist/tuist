defmodule Tuist.Repo.Migrations.AddProjectTokensTable do
  use Ecto.Migration

  def change do
    create table(:project_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :encrypted_token_hash, :string, required: true
      add :project_id, references(:projects, on_delete: :delete_all), required: true
      # credo:disable-for-next-line Credo.Checks.TimestampsType
      timestamps(type: :utc_datetime)
    end

    create index(:project_tokens, [:encrypted_token_hash], unique: true)
    create index(:project_tokens, [:project_id, :encrypted_token_hash])
  end
end
