defmodule Tuist.Repo.Migrations.ClientsKeyPairTypes do
  use Ecto.Migration

  def up do
    alter table(:oauth_clients) do
      add :key_pair_type, :jsonb, default: ~s({
        "type": "rsa",
        "modulus_size": "1024",
        "exponent_size": "65537"
      })
    end

    execute("""
      UPDATE oauth_clients
      SET key_pair_type = '{"type": "ec", "curve": "P-256"}'
      WHERE public_client_id IS NOT NULL
    """)
  end

  def down do
    alter table(:oauth_clients) do
      remove :key_pair_type
    end
  end
end
