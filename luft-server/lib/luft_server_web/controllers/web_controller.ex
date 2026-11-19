defmodule LuftServerWeb.WebController do
  @moduledoc """
  The Luft web app (`luft/web`) on every path the API and sign-in routes do
  not take. In production the release carries the Vite build in
  `priv/static`: `Plug.Static` serves its hashed `/assets`, and every other
  path gets the HTML shell, so client-side routes load. In development the
  request goes to Vite's dev server instead, so the browser sees one origin.
  """
  use LuftServerWeb, :controller

  alias LuftServer.Config

  # Paths that are never client-side routes: a miss there is a 404, not the
  # HTML shell under a script or API URL.
  @reserved ["api", "auth", "assets"]

  def show(conn, %{"path" => path}) do
    cond do
      List.first(path) in @reserved -> not_found(conn)
      # Vite serves its own dot paths (`/node_modules/.vite/deps/...`).
      vite = Config.vite_dev_server() -> proxy(conn, vite)
      # Dotfile paths (`/.env`, `/.git/config`) are 404s, as nginx answered.
      Enum.any?(path, &String.starts_with?(&1, ".")) -> not_found(conn)
      true -> shell(conn)
    end
  end

  defp shell(conn) do
    index = Application.app_dir(:luft_server, "priv/static/index.html")

    if File.regular?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, index)
    else
      not_found(conn)
    end
  end

  # Development only: Vite serves the shell, the transformed sources, the
  # worker and the core's wasm. Its HMR WebSocket connects to Vite directly
  # (`server.hmr.clientPort` in luft/web/vite.config.ts).
  defp proxy(conn, vite) do
    # The raw query string: Vite reads flags such as `?worker_file&type=module`.
    url = %{URI.parse(vite <> conn.request_path) | query: nilify(conn.query_string)}

    case Req.get(URI.to_string(url),
           headers: [accept: get_req_header(conn, "accept")],
           decode_body: false,
           compressed: false,
           retry: false
         ) do
      {:ok, response} ->
        response.headers
        |> Map.take(["content-type", "cache-control", "etag"])
        |> Enum.reduce(conn, fn {name, [value | _]}, conn ->
          put_resp_header(conn, name, value)
        end)
        |> send_resp(response.status, response.body)

      {:error, exception} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          502,
          "Vite is not reachable at #{vite} (#{Exception.message(exception)}). " <>
            "mix phx.server starts it with `mise run dev:web` in luft/; check that command's output.\n"
        )
    end
  end

  defp nilify(""), do: nil
  defp nilify(query), do: query

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})
end
