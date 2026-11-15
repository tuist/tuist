defmodule TuistWeb.DocsRedirectController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs.Paths
  alias Tuist.Docs.Redirects
  alias TuistWeb.Marketing.Localization

  # The former docs.tuist.dev served these languages. Their pages keep their
  # language prefix so the router's audited mappings to English still apply.
  @retired_locales ["pt", "pl"]

  def show(conn, %{"locale" => locale} = params) when locale in @retired_locales do
    redirect_path =
      locale
      |> Paths.public_path(Map.get(params, "path", []))
      |> append_query_string(conn.query_string)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: redirect_path)
  end

  def show(conn, params) do
    raw_locale = Map.get(params, "locale")
    path_segments = Map.get(params, "path", [])

    {locale, path_segments} =
      cond do
        is_nil(raw_locale) ->
          {"en", path_segments}

        raw_locale in Localization.all_locales() ->
          {raw_locale, path_segments}

        true ->
          {"en", [raw_locale | path_segments]}
      end

    public_path = Paths.public_path(locale, path_segments)

    # docs.tuist.dev forwards every path here, including legacy ones, so resolve
    # them now instead of sending crawlers through another redirect.
    redirect_target =
      case Redirects.resolve(public_path, conn.query_string) do
        {:ok, "http" <> _ = url} -> [external: url]
        {:ok, path} -> [to: path]
        :none -> [to: append_query_string(public_path, conn.query_string)]
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(redirect_target)
  end

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
