defmodule TuistWeb.Plugs.LegacyRedirectsPlug do
  @moduledoc """
  A plug that handles redirects from legacy URLs to their new locations.

  Add redirects to the @redirects map as `old_path => new_path` entries.
  """
  import Phoenix.Controller
  import Plug.Conn

  @docs_locale_redirect ~r{^/docs/(?<locale>[^/]+)(?<rest>/.*)?$}

  @redirects %{
    "/blog/2024/12/16/trendyol" => "/customers/trendyol",
    "/en/contributors/translate" => "/en/contributors/languages"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case docs_path_redirect(conn) || Map.get(@redirects, conn.request_path) do
      nil ->
        conn

      new_path ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: new_path)
        |> halt()
    end
  end

  defp docs_path_redirect(conn) do
    case Regex.named_captures(@docs_locale_redirect, conn.request_path) do
      %{"locale" => locale, "rest" => rest} ->
        rest = rest || ""
        path = "/#{locale}/docs#{rest}"
        if conn.query_string == "", do: path, else: "#{path}?#{conn.query_string}"

      nil ->
        nil
    end
  end
end
