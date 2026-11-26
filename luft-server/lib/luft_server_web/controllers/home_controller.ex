defmodule LuftServerWeb.HomeController do
  @moduledoc """
  The server-rendered homepage at `/`. The page is static HTML read at compile
  time; its content security policy allows only its own inline stylesheet, by
  hash, and no scripts.
  """
  use LuftServerWeb, :controller

  @page_path Path.join(__DIR__, "../pages/home.html")
  @external_resource @page_path
  @page File.read!(@page_path)

  [_, style] = Regex.run(~r/<style>(.*?)<\/style>/s, @page)
  @style_hash :sha256 |> :crypto.hash(style) |> Base.encode64()

  @policy Enum.join(
            [
              "default-src 'none'",
              "style-src 'sha256-#{@style_hash}'",
              "img-src data:",
              "frame-ancestors 'none'",
              "base-uri 'none'",
              "form-action 'none'"
            ],
            "; "
          )

  def show(conn, _params) do
    conn
    |> put_resp_header("content-security-policy", @policy)
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_content_type("text/html")
    |> send_resp(200, @page)
  end
end
