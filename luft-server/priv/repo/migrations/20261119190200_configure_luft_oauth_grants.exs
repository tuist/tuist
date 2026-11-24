defmodule LuftServer.Repo.Migrations.ConfigureLuftOauthGrants do
  use Ecto.Migration

  def up do
    # Boruta's standard adapters store the JWT itself and its rotation lineage.
    alter table(:oauth_tokens) do
      modify :value, :text
      modify :previous_token, :text
    end

    create index(:oauth_tokens, [:sub])
    create index(:oauth_tokens, [:refresh_token], where: "refresh_token IS NOT NULL")

    # Runtime client policy lives in OAuth.Clients. Keep a registry row for
    # Boruta's token foreign key; this public PKCE client has no usable secret.
    execute """
    INSERT INTO oauth_clients
      (id, name, secret, private_key, access_token_ttl, authorization_code_ttl, inserted_at, updated_at)
    VALUES
      ('6653b77b-b787-4eb2-b955-8380ea5f1478', 'Luft', '', '', 3600, 120, now(), now())
    """
  end

  def down do
    # JWTs cannot fit back into Boruta's original varchar(255). Roll back the
    # application before this migration; never truncate retained credentials.
    execute "DELETE FROM oauth_tokens WHERE client_id = '6653b77b-b787-4eb2-b955-8380ea5f1478'"
    execute "DELETE FROM oauth_clients WHERE id = '6653b77b-b787-4eb2-b955-8380ea5f1478'"
    drop index(:oauth_tokens, [:sub])
    drop index(:oauth_tokens, [:refresh_token])

    alter table(:oauth_tokens) do
      modify :value, :string
      modify :previous_token, :string
    end
  end
end
