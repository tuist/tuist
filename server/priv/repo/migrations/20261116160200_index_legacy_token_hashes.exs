defmodule Tuist.Repo.Migrations.IndexLegacyTokenHashes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create unique_index(:users, [:token_hash],
             where: "token_hash IS NOT NULL",
             concurrently: true
           )

    create unique_index(:projects, [:token_hash],
             where: "token_hash IS NOT NULL",
             concurrently: true
           )
  end
end
