defmodule LuftServerWeb.APIController do
  @moduledoc "The native API boundary: fixed Tuist upstream, server-side user credentials."
  use LuftServerWeb, :controller

  alias LuftServer.Config
  alias LuftServer.Sessions
  alias LuftServerWeb.Plugs.Authenticate

  # Only the capabilities used by Luft, never an arbitrary authenticated proxy.
  def forward(conn, %{"path" => path}) do
    if allowed?(conn.method, path) do
      with {:ok, token} <- access_token(conn),
           {:ok, response} <- request(conn, path, token) do
        respond(conn, response, path)
      else
        {:error, :reauthenticate} -> Authenticate.unauthorized(conn)
        _ -> conn |> put_status(:bad_gateway) |> json(%{error: "tuist_unavailable"})
      end
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp access_token(conn), do: Sessions.access_token(conn.assigns.session)

  defp allowed?(method, path) do
    safe = Enum.all?(path, &(&1 not in ["", ".", ".."] and not String.contains?(&1, ["/", "\\"])))

    safe and
      case {method, path} do
        {"GET", ["projects"]} ->
          true

        {"DELETE", ["accounts", _]} ->
          true

        {"GET", ["organizations", _]} ->
          true

        {verb, ["projects", _, _, "previews" | _]} ->
          verb in ["GET", "DELETE"]

        {verb, ["me", "push-devices" | _]} ->
          verb in ["GET", "PUT", "POST", "DELETE"]

        _ ->
          false
      end
  end

  defp request(conn, path, token) do
    url =
      Config.tuist_issuer() <>
        "/api/" <>
        Enum.map_join(path, "/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)

    url = if conn.query_string == "", do: url, else: url <> "?" <> conn.query_string

    options = [
      url: url,
      method: conn.method |> String.downcase() |> String.to_existing_atom(),
      auth: {:bearer, token},
      redirect: false,
      retry: false,
      receive_timeout: 65_000
    ]

    options =
      if conn.method in ["POST", "PUT", "PATCH"] do
        Keyword.put(options, :json, conn.body_params)
      else
        options
      end

    Req.request(Keyword.merge(options, Config.req_options()))
  end

  defp respond(conn, %{status: status, body: body}, _path) do
    if status == 204 do
      send_resp(conn, 204, "")
    else
      # Do not forward upstream cookies, redirects, authentication headers or HTML.
      if is_map(body) or is_list(body) do
        conn |> put_status(status) |> json(rewrite_links(body))
      else
        conn |> put_status(:bad_gateway) |> json(%{error: "invalid_upstream_response"})
      end
    end
  end

  defp rewrite_links(value) when is_list(value), do: Enum.map(value, &rewrite_links/1)

  defp rewrite_links(value) when is_map(value) do
    Map.new(value, fn {key, value} ->
      if key in ["url", "icon_url", "device_url", "qr_code_url", "download_url", "install_url"] and
           is_binary(value) do
        {key, rewrite_url(value)}
      else
        {key, rewrite_links(value)}
      end
    end)
  end

  defp rewrite_links(value), do: value

  defp rewrite_url("itms-services://?" <> query) do
    params = URI.decode_query(query)
    "itms-services://?" <> URI.encode_query(Map.update(params, "url", "", &rewrite_url/1))
  end

  defp rewrite_url(url) do
    prefix = Config.tuist_issuer() <> "/"

    if String.starts_with?(url, prefix),
      do: Config.public_url() <> "/" <> String.replace_prefix(url, prefix, ""),
      else: url
  end
end
