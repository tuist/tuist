defmodule Tuist.Repo.Migrations.IndexOauthTokenRotationLineage do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:oauth_tokens, [:previous_token],
             using: :hash,
             where: "previous_token IS NOT NULL",
             concurrently: true
           )
  end
end
