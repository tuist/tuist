defmodule LuftServer.Repo.Migrations.AddNativeRefreshReplay do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :previous_token_hash, :binary
      add :refresh_response, :binary
      add :refresh_replay_expires_at, :utc_datetime
    end

    create unique_index(:sessions, [:previous_token_hash])
  end
end
