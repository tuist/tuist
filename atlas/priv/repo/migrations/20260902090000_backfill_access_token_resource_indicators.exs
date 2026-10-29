defmodule Atlas.Repo.Migrations.BackfillAccessTokenResourceIndicators do
  use Ecto.Migration

  # Access tokens were persisted without the RFC 8707 `resource` the
  # authorization code carried, so every refresh was rejected with
  # `invalid_target` and clients had to re-run the browser flow. Copying the
  # resource back from the originating code lets already-issued refresh
  # tokens work again instead of forcing one more sign-in per client.
  def up do
    execute("""
    UPDATE oauth_tokens AS t
    SET resource = c.resource
    FROM oauth_tokens AS c
    WHERE t.type = 'access_token'
      AND t.resource IS NULL
      AND t.previous_code IS NOT NULL
      AND c.type = 'code'
      AND c.value = t.previous_code
      AND c.resource IS NOT NULL
    """)
  end

  def down do
    :ok
  end
end
