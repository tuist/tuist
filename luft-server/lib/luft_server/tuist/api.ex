defmodule LuftServer.Tuist.API do
  @moduledoc """
  Calls to the Tuist REST API on behalf of a signed-in person, with the access
  token Tuist issued to the Luft server for them (RFC 6750). The token does
  only what its scopes grant (`LuftServer.Tuist.OIDC`'s `@scope`).
  """

  alias LuftServer.Config

  @doc "The organizations the person belongs to (`GET /api/organizations`)."
  def list_organizations(access_token) do
    case Req.get(url("/api/organizations"), options(access_token)) do
      {:ok, %Req.Response{status: 200, body: %{"organizations" => organizations}}} ->
        {:ok, Enum.map(organizations, &organization/1)}

      response ->
        error(response)
    end
  end

  @doc "Creates an organization the person administers (`POST /api/organizations`)."
  def create_organization(access_token, name) do
    case Req.post(url("/api/organizations"), options(access_token, json: %{name: name})) do
      {:ok, %Req.Response{status: 200, body: %{} = organization}} ->
        {:ok, organization(organization)}

      {:ok, %Req.Response{status: 400, body: %{"message" => message}}} ->
        {:error, {:invalid, message}}

      response ->
        error(response)
    end
  end

  defp organization(organization),
    do: %{id: organization["id"], name: organization["name"], plan: organization["plan"]}

  defp error({:ok, %Req.Response{status: 401}}), do: {:error, :unauthorized}
  defp error(_response), do: {:error, :tuist_unavailable}

  defp url(path), do: Config.tuist_issuer() <> path

  defp options(access_token, options \\ []) do
    [auth: {:bearer, access_token}, receive_timeout: 10_000]
    |> Keyword.merge(Config.req_options())
    |> Keyword.merge(options)
  end
end
