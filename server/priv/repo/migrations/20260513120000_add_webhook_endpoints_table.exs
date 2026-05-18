defmodule Tuist.Repo.Migrations.AddWebhookEndpointsTable do
  use Ecto.Migration

  # Account-scoped HTTPS destinations subscribed to Tuist events.
  #
  # `url` and `signing_secret` are Cloak-encrypted via `Tuist.Vault.Binary`;
  # the bytea column type is what `Cloak.Ecto.Binary` writes back into.
  #
  # `signing_secret_last_four` mirrors the cleartext tail of the signing
  # secret so the dashboard can render a masked preview
  # (`tuist_webhook_••••…••••XYZ`) without invoking Cloak on every endpoint
  # row. It's set by the context whenever the secret is generated or
  # rotated; nullable because masking gracefully falls back to a bullets-
  # only preview when it's absent.
  #
  # `event_types` is a Postgres text array — the app-level changeset
  # enforces the catalog and requires at least one entry.
  def change do
    create table(:webhook_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :binary, null: false
      add :signing_secret, :binary, null: false
      add :signing_secret_last_four, :string
      add :event_types, {:array, :string}, null: false, default: []

      timestamps(type: :timestamptz)
    end

    create index(:webhook_endpoints, [:account_id])
  end
end
