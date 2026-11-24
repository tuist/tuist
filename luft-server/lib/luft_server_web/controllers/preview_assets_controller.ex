defmodule LuftServerWeb.PreviewAssetsController do
  @moduledoc "Preview media and signed installs stay on Luft's origin, without an HTML surface."
  use LuftServerWeb, :controller

  alias LuftServer.Config

  def show(conn, %{"asset" => asset} = params)
      when asset in [
             "icon.png",
             "manifest.plist",
             "app.ipa",
             "app.apk",
             "download",
             "qr-code.png",
             "qr-code.svg"
           ] do
    parts = [params["account"], params["project"], "previews", params["id"], asset]

    if Enum.any?(parts, &(&1 in ["", ".", ".."] or String.contains?(&1, ["/", "\\"]))) do
      not_found(conn)
    else
      fetch(conn, parts, asset)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp fetch(conn, parts, asset) do
    segments =
      Enum.map(parts, fn part ->
        URI.encode(part, &URI.char_unreserved?/1)
      end)

    url = Config.tuist_issuer() <> "/" <> Enum.join(segments, "/")
    url = if conn.query_string == "", do: url, else: url <> "?" <> conn.query_string

    case Req.get(
           url,
           Keyword.merge(
             [redirect: false, retry: false, decode_body: false],
             Config.req_options()
           )
         ) do
      {:ok, %{status: status} = response} when status in 300..399 ->
        # Tuist's signed installation endpoints redirect to object storage.
        case Req.Response.get_header(response, "location") do
          ["https://" <> _ = location] ->
            location =
              String.replace_prefix(
                location,
                Config.tuist_issuer() <> "/",
                Config.public_url() <> "/"
              )

            conn |> put_resp_header("location", location) |> send_resp(status, "")

          _ ->
            not_found(conn)
        end

      {:ok, %{status: 200, body: body} = response} ->
        type =
          response |> Req.Response.get_header("content-type") |> List.first() ||
            "application/octet-stream"

        if String.contains?(type, "text/html") do
          not_found(conn)
        else
          body =
            if asset == "manifest.plist",
              do: String.replace(body, Config.tuist_issuer() <> "/", Config.public_url() <> "/"),
              else: body

          conn
          |> put_resp_content_type(type)
          |> put_resp_header("cache-control", "no-store")
          |> send_resp(200, body)
        end

      _ ->
        not_found(conn)
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})
end
