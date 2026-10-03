defmodule AtlasWeb.Oauth.RegistrationController do
  @behaviour Boruta.Openid.DynamicRegistrationApplication

  use AtlasWeb, :controller

  import Ecto.Changeset, only: [traverse_errors: 2]

  alias Boruta.Oauth.Client
  alias Boruta.Openid
  alias Boruta.Openid.DynamicRegistrationApplication
  alias Ecto.Changeset

  @registration_key_map %{
    "client_name" => :client_name,
    "name" => :name,
    "redirect_uris" => :redirect_uris,
    "grant_types" => :supported_grant_types,
    "response_types" => :response_types,
    "token_endpoint_auth_method" => :token_endpoint_auth_method,
    "jwks" => :jwks,
    "jwks_uri" => :jwks_uri,
    "metadata" => :metadata
  }

  def register(%Plug.Conn{} = conn, params) do
    Openid.register_client(conn, normalize(params), __MODULE__)
  end

  @impl DynamicRegistrationApplication
  def client_registered(conn, %Client{} = client) do
    conn
    |> put_status(:created)
    |> json(%{
      client_id: client.id,
      client_secret: client.secret,
      client_id_issued_at: DateTime.to_unix(DateTime.utc_now()),
      client_secret_expires_at: 0,
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      grant_types: client.supported_grant_types,
      token_endpoint_auth_method: auth_method(client)
    })
  end

  @impl DynamicRegistrationApplication
  def registration_failure(conn, %Changeset{} = changeset) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "invalid_client_metadata",
      error_description: format_errors(changeset)
    })
  end

  defp format_errors(changeset) do
    changeset
    |> traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(" ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp normalize(params) when is_map(params) do
    params
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@registration_key_map, key) do
          {:ok, mapped} -> Map.put(acc, mapped, value)
          :error -> acc
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
    |> normalize_public_client_auth()
  end

  defp normalize_public_client_auth(%{token_endpoint_auth_method: "none"} = params) do
    metadata =
      params
      |> Map.get(:metadata, %{})
      |> Map.put("token_endpoint_auth_method", "none")

    params
    |> Map.delete(:token_endpoint_auth_method)
    |> Map.put(:metadata, metadata)
    |> Map.put(:confidential, false)
    |> Map.put(:public_refresh_token, true)
    |> Map.put(:public_revoke, true)
  end

  defp normalize_public_client_auth(params), do: params

  defp auth_method(%Client{metadata: %{"token_endpoint_auth_method" => method}}) when is_binary(method), do: method

  defp auth_method(%Client{token_endpoint_auth_methods: methods}) when is_list(methods) and methods != [],
    do: List.first(methods)

  defp auth_method(_), do: nil
end
