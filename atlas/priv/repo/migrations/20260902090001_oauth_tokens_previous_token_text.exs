defmodule Atlas.Repo.Migrations.OauthTokensPreviousTokenText do
  use Ecto.Migration

  # Atlas mints Guardian JWTs as access tokens, so `value` is already `text`.
  # A refresh stores the token it replaces in `previous_token`, which Boruta
  # still declares as `varchar(255)`, far too small for a JWT. Widening it is
  # a catalog-only change on Postgres, no table rewrite.
  def up do
    alter table(:oauth_tokens) do
      modify :previous_token, :text
    end
  end

  def down do
    alter table(:oauth_tokens) do
      modify :previous_token, :string
    end
  end
end
