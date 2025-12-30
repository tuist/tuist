defmodule Tuist.Repo.Migrations.MigrateAccountTokensScopes do
  use Ecto.Migration

  def change do
    # Step 1: Add new string array column
    execute(
      "ALTER TABLE account_tokens ADD COLUMN scopes_new text[] DEFAULT '{}'",
      "ALTER TABLE account_tokens DROP COLUMN IF EXISTS scopes_new"
    )

    # Step 2: Migrate existing scope values (0 = registry_read -> account:registry:read)
    execute(
      """
      UPDATE account_tokens
      SET scopes_new = CASE
        WHEN scopes @> ARRAY[0] THEN ARRAY['account:registry:read']
        ELSE '{}'
      END
      """,
      "SELECT 1"
    )

    # Step 3: Drop old column and rename new one
    execute(
      "ALTER TABLE account_tokens DROP COLUMN scopes",
      "ALTER TABLE account_tokens ADD COLUMN scopes integer[] DEFAULT '{}'"
    )

    execute(
      "ALTER TABLE account_tokens RENAME COLUMN scopes_new TO scopes",
      "ALTER TABLE account_tokens RENAME COLUMN scopes TO scopes_new"
    )

    execute(
      "ALTER TABLE account_tokens ALTER COLUMN scopes SET NOT NULL",
      "ALTER TABLE account_tokens ALTER COLUMN scopes DROP NOT NULL"
    )
  end
end
