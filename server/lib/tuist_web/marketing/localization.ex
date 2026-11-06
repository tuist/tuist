defmodule TuistWeb.Marketing.Localization do
  @moduledoc ~S"""
  This module contains utilities to handle localization in the marketing pages:

  - Plugs and LiveView on_mount callbacks to set the local to the process using `Gettext.put_locale/1`
  - Root-only browser language detection and explicit, persistent language selection.
  """
  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.Locale

  @languages Tuist.Locale.languages()
  @preference_cookie "tuist_locale"

  @additional_locales @languages
                      |> Enum.map(& &1.code)
                      |> Enum.reject(&(&1 == "en"))

  def init(:put_locale), do: :put_locale
  def init(:negotiate_locale), do: :negotiate_locale

  def languages, do: @languages
  def all_locales, do: Enum.map(@languages, & &1.code)
  def additional_locales, do: @additional_locales

  def call(%{method: method} = conn, :negotiate_locale) when method in ["GET", "HEAD"] do
    selected_locale = conn.query_params["set_locale"]

    cond do
      selected_locale in all_locales() and selected_locale == conn.private[:locale] ->
        query =
          conn.query_string
          |> URI.query_decoder()
          |> Enum.reject(fn {key, _value} -> key == "set_locale" end)
          |> URI.encode_query()

        target = %URI{path: conn.request_path, query: if(query != "", do: query)}

        conn
        |> private_response()
        |> put_resp_cookie(@preference_cookie, selected_locale,
          max_age: 60 * 60 * 24 * 365,
          http_only: true,
          same_site: "Lax",
          secure: conn.scheme == :https
        )
        |> Phoenix.Controller.redirect(to: URI.to_string(target))
        |> halt()

      conn.request_path == "/" ->
        conn = conn |> fetch_cookies() |> private_response()
        locale = preferred_locale(conn)

        if locale in additional_locales() and conn.query_params["disable_locale_redirect"] != "true" do
          target = %URI{path: locale_path_prefix(locale), query: if(conn.query_string != "", do: conn.query_string)}
          conn |> Phoenix.Controller.redirect(to: URI.to_string(target)) |> halt()
        else
          conn
        end

      true ->
        conn
    end
  end

  def call(conn, :negotiate_locale), do: conn

  def call(conn, :put_locale) do
    locale = Map.get(conn.private, :locale)

    if is_nil(locale) do
      conn
    else
      Gettext.put_locale(locale)

      maybe_put_locale_session(conn, locale)
    end
  end

  def language_switch_href(path, locale) do
    uri = path |> localized_href(locale) |> URI.parse()

    query =
      (uri.query || "")
      |> URI.query_decoder()
      |> Enum.reject(fn {key, _value} -> key == "set_locale" end)
      |> Enum.concat([{"set_locale", locale}])
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  defp preferred_locale(conn) do
    preference = conn.cookies[@preference_cookie]

    if preference in all_locales() do
      preference
    else
      conn
      |> get_req_header("accept-language")
      |> Enum.join(",")
      |> Locale.locale_from_accept_language()
    end
  end

  defp private_response(conn) do
    register_before_send(conn, fn conn ->
      put_resp_header(conn, "cache-control", "private, no-store")
    end)
  end

  def path_without_locale(path) do
    Enum.reduce(all_locales(), path, fn locale, acc ->
      # For marketing URLs, English uses "/" as prefix
      # For docs URLs, we need to handle "/en/docs/..." explicitly
      locale_prefix = if locale == "en", do: "/en", else: locale_path_prefix(locale)

      # Handle paths like /ko/ or /ko/pricing using regex
      if String.contains?(acc, "/") do
        prefix = "^" <> Regex.escape(locale_prefix) <> "(?=/|$)"
        result = Regex.replace(~r/#{prefix}/, acc, "")
        if result == "", do: "/", else: result
      else
        acc
      end
    end)
  end

  def locale_path_prefix("en") do
    "/"
  end

  def locale_path_prefix(locale) do
    "/#{locale}"
  end

  def on_mount(:default, _params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)
    {:cont, socket}
  end

  # Marketing responses declare `public, max-age=60, stale-while-revalidate=86400`,
  # but a CDN will not store a response carrying `Set-Cookie`. Re-stamping an
  # unchanged locale on every request made the entire marketing site
  # uncacheable at the edge, so only write when the value actually changes.
  defp maybe_put_locale_session(conn, locale) do
    if get_session(conn, :locale) == locale do
      conn
    else
      put_session(conn, :locale, locale)
    end
  end

  @doc """
  Localizes a URL path based on the current locale.

  For tuist.dev docs URLs, updates the locale segment in the path.
  For relative marketing URLs, prepends locale (except for English which has no prefix).
  External URLs that are not tuist.dev docs are returned as-is.
  """
  def localized_href(href) do
    locale = Gettext.get_locale(TuistWeb.Gettext)
    localized_href(href, locale)
  end

  @doc """
  Localizes a URL path to a specific target locale.

  For tuist.dev docs URLs, updates the locale segment in the path.
  For relative marketing URLs, prepends locale (except for English which has no prefix).
  External URLs that are not tuist.dev docs are returned as-is.
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def localized_href(href, target_locale) do
    uri = URI.parse(href)

    cond do
      # Handle non-http(s) schemes (mailto, tel, etc.)
      not is_nil(uri.scheme) and uri.scheme not in ["http", "https"] ->
        href

      # Handle tuist.dev docs URLs (tuist.dev/LOCALE/docs/...)
      uri.host == "tuist.dev" and docs_path?(uri.path) ->
        docs_subpath = extract_docs_subpath(uri.path)
        localized_path = "/#{target_locale}/docs#{docs_subpath}"

        uri
        |> Map.put(:path, localized_path)
        |> URI.to_string()

      # Handle relative marketing URLs (no host and no scheme means relative)
      is_nil(uri.host) and is_nil(uri.scheme) and not is_nil(uri.path) ->
        if target_locale == "en" do
          # For English, remove any locale prefix
          path_without_locale = path_without_locale(uri.path)

          uri
          |> Map.put(:path, path_without_locale)
          |> URI.to_string()
        else
          # Remove any existing locale prefix first
          path_without_locale = path_without_locale(uri.path)

          # Build the localized path
          localized_path =
            if path_without_locale == "/" do
              locale_path_prefix(target_locale)
            else
              locale_path_prefix(target_locale) <> path_without_locale
            end

          uri
          |> Map.put(:path, localized_path)
          |> URI.to_string()
        end

      # Return as-is for other external URLs
      true ->
        href
    end
  end

  defp docs_path?(nil), do: false

  defp docs_path?(path) do
    Enum.any?(all_locales(), fn locale -> String.starts_with?(path, "/#{locale}/docs") end)
  end

  defp extract_docs_subpath(path) do
    result =
      Enum.reduce(all_locales(), path, fn locale, acc ->
        prefix = "/#{locale}/docs"

        if String.starts_with?(acc, prefix) do
          String.replace_prefix(acc, prefix, "")
        else
          acc
        end
      end)

    if result == "" or result == path, do: "", else: result
  end

  @doc """
  Returns the current path from the connection, suitable for use in language switchers.
  Gets the path from conn.assigns.current_path or falls back to conn.request_path.
  """
  def current_path(assigns) do
    Map.get(assigns, :current_path, "/")
  end
end
