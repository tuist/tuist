defmodule TuistWeb.Plugs.LegacyAccountTokenScopesPlug do
  @moduledoc """
  A plug that transforms legacy account token scopes to the new format.

  This provides backwards compatibility with CLI versions <4.111.1 that use
  the old scope format (e.g., "registry_read" instead of "account:registry:read").
  """

  @legacy_scope_mapping %{
    "registry_read" => "account:registry:read"
  }

  def init(opts), do: opts

  def call(%{body_params: %{"scopes" => scopes}} = conn, _opts) when is_list(scopes) do
    normalized_scopes = Enum.map(scopes, &normalize_scope/1)

    Map.put(conn, :body_params, Map.put(conn.body_params, "scopes", normalized_scopes))
  end

  def call(conn, _opts), do: conn

  defp normalize_scope(scope) do
    Map.get(@legacy_scope_mapping, scope, scope)
  end
end
