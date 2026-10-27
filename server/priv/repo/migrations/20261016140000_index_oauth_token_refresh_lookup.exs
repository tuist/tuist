defmodule Tuist.Repo.Migrations.IndexOauthTokenRefreshLookup do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:oauth_tokens, [:refresh_token],
             where: "refresh_token IS NOT NULL",
             concurrently: true
           )
  end
end
