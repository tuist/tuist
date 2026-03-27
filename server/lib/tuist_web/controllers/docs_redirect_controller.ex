defmodule TuistWeb.DocsRedirectController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs.Paths
  alias TuistWeb.Marketing.Localization

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

    redirect_path =
      locale
      |> Paths.public_path(path_segments)
      |> append_query_string(conn.query_string)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: redirect_path)
  end

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
