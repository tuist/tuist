defmodule Atlas.Repo.Migrations.CreateMcpGrantRequests do
  use Ecto.Migration

  # The grant comes back from ops on a plain authenticated GET, so without a
  # record of having asked, Atlas would store whatever a crafted link handed it
  # — replacing a working grant with a useless one. A row is created when the
  # operator asks, and consumed when the redirect returns, so a link can be
  # followed once and only by the person who started it.
  def change do
    create table(:mcp_grant_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_name, :string, null: false
      add :account_handle, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:mcp_grant_requests, [:user_id])
    create index(:mcp_grant_requests, [:expires_at])
  end
end
