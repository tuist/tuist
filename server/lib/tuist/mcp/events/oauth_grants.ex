defmodule Tuist.MCP.Events.OAuthGrants do
  @moduledoc false

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Ecto.Adapters.SQL
  alias Tuist.Repo

  def find_bearer(bearer, client_id, user_id) do
    Repo.one(
      from token in Token,
        where:
          token.value == ^bearer and token.client_id == ^client_id and token.sub == ^to_string(user_id) and
            token.type == "access_token" and not is_nil(token.refresh_token) and
            is_nil(token.revoked_at) and is_nil(token.refresh_token_revoked_at)
    )
  end

  def root_id(%Token{previous_token: nil, id: id}), do: {:ok, id}

  def root_id(%Token{id: id, client_id: client_id, sub: user_id}) do
    query = """
    WITH RECURSIVE grant_ancestors AS (
      SELECT id, previous_token, client_id, sub, 0 AS depth
      FROM oauth_tokens
      WHERE id = $1 AND client_id = $2 AND sub = $3
      UNION ALL
      SELECT parent.id, parent.previous_token, parent.client_id, parent.sub, child.depth + 1
      FROM oauth_tokens AS parent
      JOIN grant_ancestors AS child ON parent.value = child.previous_token
      WHERE parent.client_id = child.client_id AND parent.sub = child.sub AND parent.type = 'access_token'
    )
    SELECT id FROM grant_ancestors ORDER BY depth DESC LIMIT 1
    """

    case SQL.query(Repo, query, [Ecto.UUID.dump!(id), Ecto.UUID.dump!(client_id), user_id]) do
      {:ok, %{rows: [[root_id]]}} -> {:ok, Ecto.UUID.load!(root_id)}
      _ -> {:error, :grant_unavailable}
    end
  end

  def active_scope(grant_id, client_id, user_id, refresh_token_ttl) do
    query = """
    WITH RECURSIVE grant_lineage AS (
      SELECT id, value, client_id, sub, scope, inserted_at, revoked_at, refresh_token_revoked_at, refresh_token
      FROM oauth_tokens
      WHERE id = $1 AND client_id = $2 AND sub = $3 AND type = 'access_token'
      UNION ALL
      SELECT child.id, child.value, child.client_id, child.sub, child.scope, child.inserted_at,
             child.revoked_at, child.refresh_token_revoked_at, child.refresh_token
      FROM oauth_tokens AS child
      JOIN grant_lineage AS parent ON child.previous_token = parent.value
      WHERE child.client_id = parent.client_id AND child.sub = parent.sub AND child.type = 'access_token'
    )
    SELECT scope, inserted_at
    FROM grant_lineage
    WHERE revoked_at IS NULL AND refresh_token_revoked_at IS NULL AND refresh_token IS NOT NULL
    ORDER BY inserted_at DESC
    LIMIT 1
    """

    case SQL.query(Repo, query, [Ecto.UUID.dump!(grant_id), Ecto.UUID.dump!(client_id), to_string(user_id)]) do
      {:ok, %{rows: [[scope, inserted_at]]}}
      when is_binary(scope) and not is_nil(inserted_at) ->
        issued_at = DateTime.from_naive!(inserted_at, "Etc/UTC")

        if DateTime.after?(DateTime.add(issued_at, refresh_token_ttl, :second), DateTime.utc_now()),
          do: {:ok, scope},
          else: :error

      _ ->
        :error
    end
  end
end
