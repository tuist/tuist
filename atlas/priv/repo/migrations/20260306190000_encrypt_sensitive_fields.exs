defmodule Atlas.Repo.Migrations.EncryptSensitiveFields do
  use Ecto.Migration

  def up do
    # Drop NOT NULL constraints first, then convert to binary for encrypted storage.
    # Existing plaintext values are cleared since they must be re-entered encrypted.
    execute "ALTER TABLE slack_integrations ALTER COLUMN bot_token DROP NOT NULL"
    execute "ALTER TABLE slack_integrations ALTER COLUMN signing_secret DROP NOT NULL"
    execute "ALTER TABLE slack_integrations ALTER COLUMN bot_token TYPE bytea USING NULL"
    execute "ALTER TABLE slack_integrations ALTER COLUMN signing_secret TYPE bytea USING NULL"

    execute "ALTER TABLE github_apps ALTER COLUMN webhook_secret DROP NOT NULL"
    execute "ALTER TABLE github_apps ALTER COLUMN private_key DROP NOT NULL"
    execute "ALTER TABLE github_apps ALTER COLUMN webhook_secret TYPE bytea USING NULL"
    execute "ALTER TABLE github_apps ALTER COLUMN private_key TYPE bytea USING NULL"
  end

  def down do
    execute "ALTER TABLE slack_integrations ALTER COLUMN bot_token TYPE varchar USING NULL"
    execute "ALTER TABLE slack_integrations ALTER COLUMN signing_secret TYPE varchar USING NULL"

    execute "ALTER TABLE github_apps ALTER COLUMN webhook_secret TYPE varchar USING NULL"
    execute "ALTER TABLE github_apps ALTER COLUMN private_key TYPE text USING NULL"
  end
end
