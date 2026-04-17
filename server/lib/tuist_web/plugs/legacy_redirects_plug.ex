defmodule TuistWeb.Plugs.LegacyRedirectsPlug do
  @moduledoc """
  A plug that handles redirects from legacy URLs to their new locations.

  Three kinds of redirects are applied, in order:

    1. `/docs/<locale>/*` → `/<locale>/docs/*` normalization (old URL shape)
    2. Flat `@redirects` map for one-off cross-site redirects
    3. Docs content redirects from `Tuist.Docs.Redirects`, applied after
       step 1 so a URL like `/docs/en/cli/foo` is normalized and then
       routed to its new location.

  For content redirects within the documentation (docs renamed or
  reorganized), add rules to `Tuist.Docs.Redirects`, not here.
  """
  import Phoenix.Controller
  import Plug.Conn

  alias Tuist.Docs.Redirects

  @docs_locale_redirect ~r{^/docs/(?<locale>[^/]+)(?<rest>/.*)?$}

  @redirects %{
    "/blog/2024/12/16/trendyol" => "/customers/trendyol",
    "/en/contributors/translate" => "/en/contributors/languages"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case resolve(conn) do
      nil ->
        conn

      new_path ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: new_path)
        |> halt()
    end
  end

  defp resolve(conn) do
    normalized_request_path = normalize_docs_path(conn.request_path)
    path_for_docs_lookup = normalized_request_path || conn.request_path

    case Redirects.resolve(path_for_docs_lookup, conn.query_string) do
      {:ok, docs_redirect} ->
        docs_redirect

      :none ->
        normalized_request_path &&
          append_query_string(normalized_request_path, conn.query_string)
    end || Map.get(@redirects, conn.request_path)
  end

  defp normalize_docs_path(request_path) do
    case Regex.named_captures(@docs_locale_redirect, request_path) do
      %{"locale" => locale, "rest" => rest} -> "/#{locale}/docs#{rest || ""}"
      nil -> nil
    end
  end

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
