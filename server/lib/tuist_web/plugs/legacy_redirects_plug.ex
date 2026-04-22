defmodule TuistWeb.Plugs.LegacyRedirectsPlug do
  @moduledoc """
  A plug that handles redirects from legacy URLs to their new locations.

  Three kinds of redirects are applied, in order:

    1. `docs.tuist.dev/*` -> `tuist.dev/<locale>/docs/*` host migration
    2. `/docs/<locale>/*` -> `/<locale>/docs/*` normalization
    3. Documentation redirects from `Tuist.Docs.Redirects`
    4. Flat `@redirects` entries for one-off non-docs redirects
  """
  import Phoenix.Controller
  import Plug.Conn

  alias Tuist.Docs.Redirects
  alias Tuist.Environment
  alias TuistWeb.RequestOrigin

  @docs_locale_redirect ~r{^/docs/(?<locale>[^/]+)(?<rest>/.*)?$}
  @legacy_docs_host "docs.tuist.dev"

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
        |> redirect(redirect_target(new_path))
        |> halt()
    end
  end

  defp resolve(conn) do
    legacy_docs_host_path = legacy_docs_host_path(conn)
    normalized_request_path = normalize_docs_path(conn.request_path)
    path_for_docs_lookup = legacy_docs_host_path || normalized_request_path || conn.request_path

    case Redirects.resolve(path_for_docs_lookup, conn.query_string) do
      {:ok, docs_redirect} ->
        maybe_externalize_docs_redirect(docs_redirect, legacy_docs_host_path)

      :none ->
        cond do
          legacy_docs_host_path ->
            externalize_to_app_url(legacy_docs_host_path, conn.query_string)

          normalized_request_path ->
            append_query_string(normalized_request_path, conn.query_string)

          true ->
            nil
        end
    end ||
      Map.get(@redirects, conn.request_path)
  end

  defp normalize_docs_path(request_path) do
    case Regex.named_captures(@docs_locale_redirect, request_path) do
      %{"locale" => locale, "rest" => rest} -> "/#{locale}/docs#{rest || ""}"
      nil -> nil
    end
  end

  defp legacy_docs_host_path(conn) do
    if request_host(conn) == @legacy_docs_host do
      Redirects.legacy_host_path(conn.request_path)
    end
  end

  defp request_host(conn) do
    conn
    |> RequestOrigin.from_conn()
    |> URI.parse()
    |> Map.get(:host)
  end

  defp maybe_externalize_docs_redirect("http" <> _ = path, _legacy_docs_host_path), do: path
  defp maybe_externalize_docs_redirect(path, nil), do: path
  defp maybe_externalize_docs_redirect(path, _legacy_docs_host_path), do: externalize_to_app_url(path)

  defp externalize_to_app_url(path_with_query, query_string \\ nil) do
    %{path: path, query: query} = URI.parse(path_with_query)
    base_uri = URI.parse(Environment.app_url())

    URI.to_string(%{
      base_uri
      | path: path,
        query: query || normalize_query_string(query_string)
    })
  end

  defp redirect_target("http" <> _ = path), do: [external: path]
  defp redirect_target(path), do: [to: path]

  defp normalize_query_string(nil), do: nil
  defp normalize_query_string(""), do: nil
  defp normalize_query_string(query_string), do: query_string

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
