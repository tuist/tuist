defmodule Tuist.Repo.Migrations.AddSecretLastFourToKuraSelfHostedClients do
  use Ecto.Migration

  # Stores the last four characters of the client secret so the dashboard can
  # render a masked preview (mirroring webhook signing secrets), letting a
  # customer match a credential against a secret stored elsewhere without
  # weakening the credential. Nullable with no backfill: credentials issued
  # before this migration render as fully masked.
  def change do
    alter table(:kura_self_hosted_clients) do
      add :secret_last_four, :string
    end
  end
end
