defmodule TuistWeb.Plugs.SCIMAuthPlug do
  @moduledoc """
  Authenticates SCIM 2.0 requests using a per-organization bearer token.

  On success, assigns:
    * `:scim_organization` - the resolved `%Organization{}` (with `:account` preloaded)
    * `:scim_token` - the matched `%Tuist.Accounts.AccountToken{}`
    * `:scim_base_url` - the absolute URL prefix for the org's SCIM endpoints

  On failure, halts with a SCIM-formatted 401 Unauthorized response.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.SCIM
  alias Tuist.SCIM.Resource

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        deny(conn, "Missing bearer token")

      token ->
        case SCIM.authenticate_token(token) do
          {:ok, organization, scim_token} ->
            SCIM.touch_token(scim_token)

            conn
            |> assign(:scim_organization, organization)
            |> assign(:scim_token, scim_token)
            |> assign(:scim_base_url, base_url(conn))

          {:error, _} ->
            deny(conn, "Invalid bearer token")
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      ["bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  # Honors X-Forwarded-Proto and X-Forwarded-Host so meta.location URLs in
  # SCIM responses are correct when running behind a tunnel/proxy (ngrok,
  # Cloudflare, Render).
  defp base_url(conn) do
    forwarded_scheme = first_forwarded(conn, "x-forwarded-proto")
    forwarded_host = first_forwarded(conn, "x-forwarded-host")

    scheme = forwarded_scheme || Atom.to_string(conn.scheme)

    {host, port_suffix} =
      if is_binary(forwarded_host) do
        {forwarded_host, ""}
      else
        {conn.host, default_port_suffix(scheme, conn.port)}
      end

    "#{scheme}://#{host}#{port_suffix}/scim/v2"
  end

  defp first_forwarded(conn, header) do
    case get_req_header(conn, header) do
      [value | _] -> value |> String.split(",") |> List.first() |> String.trim() |> downcase_if_scheme(header)
      _ -> nil
    end
  end

  defp downcase_if_scheme(value, "x-forwarded-proto"), do: String.downcase(value)
  defp downcase_if_scheme(value, _), do: value

  defp default_port_suffix("https", _port), do: ""
  defp default_port_suffix("http", 80), do: ""
  defp default_port_suffix(_scheme, port), do: ":#{port}"

  defp deny(conn, detail) do
    body = Resource.render_error(401, detail)

    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="tuist-scim"))
    |> put_resp_content_type("application/scim+json")
    |> send_resp(401, JSON.encode!(body))
    |> halt()
  end
end
