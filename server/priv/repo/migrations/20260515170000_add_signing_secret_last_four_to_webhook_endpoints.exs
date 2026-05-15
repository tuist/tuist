defmodule Tuist.Repo.Migrations.AddSigningSecretLastFourToWebhookEndpoints do
  use Ecto.Migration

  alias Tuist.Repo

  # The last 4 characters of the signing secret are a cosmetic
  # identifier — same convention Stripe, GitHub, and Sentry use — so
  # operators can match a stored secret against the table without
  # decrypting. Storing them in their own non-encrypted column lets the
  # dashboard render every endpoint row without invoking Cloak; the
  # delivery worker is the only path that still needs the full plaintext.
  #
  # Left nullable: the dashboard's `masked_signing_secret/1` falls back
  # to the bullets-only mask when the column is empty. New endpoints
  # and rotations populate it from `Tuist.Webhooks.Signature.generate_secret/0`'s
  # plaintext at the call site, so we don't need to reach back through
  # Cloak in the migration context.
  def up do
    unless column_exists?("webhook_endpoints", "signing_secret_last_four") do
      alter table(:webhook_endpoints) do
        add :signing_secret_last_four, :string
      end
    end
  end

  def down do
    alter table(:webhook_endpoints) do
      remove :signing_secret_last_four
    end
  end

  defp column_exists?(table, column) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT 1 FROM information_schema.columns
        WHERE table_name = $1 AND column_name = $2
        """,
        [table, column]
      )

    rows != []
  end
end
