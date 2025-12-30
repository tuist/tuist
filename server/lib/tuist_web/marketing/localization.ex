defmodule TuistWeb.Marketing.Localization do
  @moduledoc ~S"""
  This module contains utilities to handle localization in the marketing pages:

  - Plugs and LiveView on_mount callbacks to set the local to the process using `Gettext.put_locale/1`
  - Logic to extract the locale from the `Accept-Language` header.
  - Logic to redirect to the localized route based on the locale extracted from the `Accept-Language` header.
  """
  @behaviour Plug

  import Plug.Conn

  @languages [
    %{code: "en", label: "English", native: "English"},
    %{code: "ar", label: "Arabic", native: "العربية"},
    %{code: "es", label: "Spanish", native: "Castellano"},
    %{code: "ja", label: "Japanese", native: "日本語"},
    %{code: "ko", label: "Korean", native: "한국어"},
    %{code: "pl", label: "Polish", native: "Polski"},
    %{code: "pt", label: "Portuguese", native: "Português"},
    %{code: "ru", label: "Russian", native: "Русский"},
    %{code: "yue_Hant", label: "Cantonese", native: "廣東話"},
    %{code: "zh_Hans", label: "Chinese", native: "中文"}
  ]

  @additional_locales @languages
                      |> Enum.map(& &1.code)
                      |> Enum.reject(&(&1 == "en"))

  def init(:put_locale), do: :put_locale
  def init(:redirect_to_localized_route), do: :redirect_to_localized_route

  def languages, do: @languages
  def all_locales, do: Enum.map(@languages, & &1.code)
  def additional_locales, do: @additional_locales

  def call(conn, :put_locale) do
    locale = Map.get(conn.private, :locale)

    if is_nil(locale) do
      conn
    else
      Gettext.put_locale(locale)

      conn
      |> put_session(:locale, locale)
      |> put_resp_cookie("user_locale_preference", locale,
        max_age: 60 * 60 * 24 * 365,
        http_only: true,
        same_site: "Lax"
      )
    end
  end

  def call(conn, :redirect_to_localized_route) do
    private_locale = Map.get(conn.private, :locale, "en")
    headers_locale = fetch_locale_from_headers(conn) || "en"

    # Check if user has explicitly disabled redirect via query param or cookie
    disable_locale_redirect =
      Map.get(conn.query_params, "disable_locale_redirect", "false") == "true" or
        has_user_locale_preference?(conn)

    # Only redirect when:
    # 1. User is on English pages (private_locale == "en")
    # 2. Browser language is a different supported locale
    # 3. Redirect is not disabled (no query param or user preference)
    should_redirect =
      private_locale == "en" and
        Enum.member?(additional_locales(), headers_locale) and
        !disable_locale_redirect

    if should_redirect do
      redirect_to_path =
        Path.join(
          locale_path_prefix(headers_locale),
          if(conn.query_string == "",
            do: path_without_locale(conn.request_path),
            else: "#{path_without_locale(conn.request_path)}?#{conn.query_string}"
          )
        )

      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(
        to: redirect_to_path,
        status: 301
      )
      |> halt()
    else
      conn
    end
  end

  def path_without_locale(path) do
    Enum.reduce(all_locales(), path, fn locale, acc ->
      # For marketing URLs, English uses "/" as prefix
      # For docs URLs, we need to handle "/en/" explicitly
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

  defp fetch_locale_from_headers(conn) do
    conn
    |> locales_from_accept_language()
    |> Enum.map(fn locale -> validate_locale(locale) end)
    |> Enum.find(&(not is_nil(&1)))
  end

  # Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7
  defp locales_from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [value | _] ->
        values = String.split(value, ",")
        Enum.map(values, &resolve_locale_from_accept_language/1)

      _ ->
        []
    end
  end

  defp resolve_locale_from_accept_language(language) do
    language
    |> String.split(";")
    |> List.first()
    |> language_to_locale()
  end

  defp language_to_locale(language) do
    String.replace(language, "-", "_", global: false)
  end

  defp validate_locale(nil), do: nil

  defp validate_locale(locale) do
    supported_locales = Gettext.known_locales(TuistWeb.Gettext)

    case String.split(locale, "_") do
      [language, _] ->
        Enum.find([language, locale], fn locale ->
          locale in supported_locales
        end)

      [^locale] ->
        if locale in supported_locales do
          locale
        end
    end
  end

  defp has_user_locale_preference?(conn) do
    # Check if user has a locale preference cookie set
    # This cookie is set when user explicitly switches language
    case Map.get(conn.req_cookies, "user_locale_preference") do
      nil -> false
      _value -> true
    end
  end

  @doc """
  Localizes a URL path based on the current locale.

  For docs.tuist.dev URLs, inserts locale after domain (or replaces existing locale).
  For relative marketing URLs, prepends locale (except for English which has no prefix).
  External URLs that are not docs.tuist.dev are returned as-is.
  """
  def localized_href(href) do
    locale = Gettext.get_locale(TuistWeb.Gettext)
    localized_href(href, locale)
  end

  @doc """
  Localizes a URL path to a specific target locale.

  For docs.tuist.dev URLs, inserts locale after domain (or replaces existing locale).
  For relative marketing URLs, prepends locale (except for English which has no prefix).
  External URLs that are not docs.tuist.dev are returned as-is.
  """
  def localized_href(href, target_locale) do
    uri = URI.parse(href)

    cond do
      # Handle non-http(s) schemes (mailto, tel, etc.)
      not is_nil(uri.scheme) and uri.scheme not in ["http", "https"] ->
        href

      # Handle docs.tuist.dev URLs
      uri.host == "docs.tuist.dev" ->
        clean_path = path_without_locale(uri.path || "/")
        localized_path = "/#{target_locale}#{clean_path}"

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

  @doc """
  Returns the current path from the connection, suitable for use in language switchers.
  Gets the path from conn.assigns.current_path or falls back to conn.request_path.
  """
  def current_path(assigns) do
    Map.get(assigns, :current_path, "/")
  end
end
